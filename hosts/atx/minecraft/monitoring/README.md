# servu monitoring

A standard-library Go HTTP exporter, running inside the Minecraft microVM as
`veeti`. It sends no commands to Minecraft and requires no game plugin, RCON,
public port or firewall changes.

- Metrics: `127.0.0.1:9150/metrics`, scraped by the existing vmagent every 30s.
- Logs/process, saved player stats and backup-attempt status: refreshed every 10s.
- Allocated disk space (including BlueMap) and Restic snapshot metadata: refreshed every 5m, outside the HTTP
  request path. External commands have timeouts. Unchanged log archives are cached.
- Grafana: **Minecraft · servu**, provisioned on the backup host.

## Deployment

From the repository root, using the existing deployment helper:

```sh
./deploy atx 192.168.40.10
./deploy backup backup.internal.veetik.com
```

Updating ATX changes the Minecraft microVM generation. Verify the guest actually
runs the new generation; depending on the microVM update lifecycle, activating
that generation may require restarting the guest (which interrupts Minecraft).
Do not assume a host switch alone updated a running guest.

Inside the guest:

```sh
systemctl status minecraft-metrics
journalctl -u minecraft-metrics
curl -fsS http://127.0.0.1:9150/metrics
```

Backup attempt status becomes available after the updated backup script first
runs. Snapshot metadata and repository size work independently of that status.
Storage collection can take a little while on the initial pass.

## Existing player history (explicit one-time import)

After the exporter package is installed, generate historical samples locally:

```sh
ssh veeti@192.168.76.2 'minecraft-metrics --history --timezone UTC' > servu-history.jsonl
```

This reads logs only; it does **not** import anything automatically. The VM was
verified to use UTC. Do not substitute your browser's timezone for the log timezone.

The authenticated public metrics endpoint only accepts remote-write requests,
not historical imports. Open a temporary SSH tunnel to VictoriaMetrics on the
backup host instead, in another terminal:

```sh
ssh -N -L 18428:127.0.0.1:18428 veeti@backup.internal.veetik.com
```

Inspect the generated JSON first, then explicitly import:

```sh
curl --fail-with-body --data-binary @servu-history.jsonl \
  http://127.0.0.1:18428/api/v1/import
```

Close the tunnel afterwards. Run this once, ideally when initially enabling live
collection, to avoid conflicting overlapping live/historical samples. The import
uses the same `server`, `job`, `host` and `instance` labels as the guest's vmagent.
It generates player presence and player-count samples at 30-second intervals,
ending at the final log event; CPU, memory and storage cannot be backfilled from
these game logs.

## Semantics and limitations

- Player names are taken literally from join/leave events, including numeric names.
  Failed login/disconnect messages are not joins or leaves. `[AFK]` is stripped
  from player-list entries, not treated as part of a username.
- Connected time includes AFK, not just active gameplay. Selected-range playtime
  is an approximate integral of 30-second presence samples.
- Saved player stats expose game-recorded playtime (ticks divided by 20), deaths,
  mob kills, jumps, logouts, mined blocks, crafted items and distance by movement
  mode. These include history present in the world even when the corresponding
  logs are gone. They update when Minecraft saves the files, not every game tick.
  Tick-derived playtime is not an exact wall-clock duration under server lag.
  UUID labels preserve identity, and usercache maps UUIDs to display names; a
  missing cache entry falls back to UUID. Per-item/block/entity labels are avoided.
  A stats-file age is provided: offline players' old files are normal.
- `minecraft_player_retained_log_seconds` is a **gauge**, reconstructed from
  retained logs, not a monotonic lifetime counter. Deleting logs can reduce it.
  State is rebuilt from those logs after a restart; no separate database is needed.
- Online-player lists and server starts establish known state. A join alone does
  not establish a complete player list. After 30 minutes without log evidence,
  live state becomes unknown until another list/start establishes it. This threshold
  relies on servu's backup job writing a player list every 12–18 minutes. Historical
  sessions with explicit joins/leaves are preserved even through long quiet periods.
- Abrupt crashes have no exact logout timestamp. On an unclean restart, open
  sessions are capped at the last log evidence rather than counted through the
  downtime. Historical samples omit the gap before the restart rather than show
  the player online through it. Missing archives or clock changes can still limit
  reconstruction.
- Java is identified by its executable and exact working directory. Multiple
  matching Java processes cause an explicit collection error rather than guessing.
  RAM is resident process memory, not JVM heap. CPU counters carry PID/start-time
  labels so process restarts do not join unrelated counters. Process uptime, OS
  thread count and Linux physical read/write-byte counters are also exposed.
  Physical I/O excludes cached reads; unavailable I/O has an explicit health metric.
- Storage uses `du -s -B1` (allocated bytes). Server includes world; world includes
  its dimensions. These overlapping sizes must not be summed. BlueMap rendered
  maps are measured separately. Fast filesystem capacity/free/available metrics
  use Linux statfs on the server directory's filesystem (currently /home), so
  the dashboard does not depend on node exporter's mount namespace. Available
  space excludes root-reserved blocks; used space is total minus free blocks.
- Restic snapshots are read with `--no-lock` to avoid modifying the repository.
  Concurrent pruning can cause a transient collection error; absent/failed data
  is not reported as zero. The configured local repository password matches the
  existing backup script. Repositories are on the same VM storage, not off-host.
- Backup attempt duration includes retention/pruning. Failed attempts preserve
  the previous success timestamp. A SIGKILL can leave `in_progress=1` until the
  next attempt; use its attempt timestamp and systemd logs to investigate.
- The saving-disabled metric reports the backup script's recovery marker, not
  a direct assertion about the server's internal save state.

## Development

```sh
cd hosts/atx/minecraft/monitoring
gofmt -w *.go
go test -race ./...
go vet ./...
```

The Nix package also runs Go tests during its build. Backup status tests:

```sh
cd hosts/atx/minecraft/backup
python3 -m unittest test_monitoring_status.py
```
