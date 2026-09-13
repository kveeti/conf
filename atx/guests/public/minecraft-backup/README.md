# Minecraft server backups

The script discovers every direct server directory under
`/home/veeti/servers/`. It takes no server, pane or destination arguments.
Symlinked directories are not followed.

For a server named `servu`:

- Server files: `/home/veeti/servers/servu/`
- tmux session: `servu`
- Restic repository: `/home/veeti/backups/servu/repository/`
- Backup state: `/home/veeti/backups/servu/`

The repository password is hardcoded as `minecraft`. This protects against
accidental access, not an attacker who can read this config or the VM.
Restic still encrypts repository data as part of its format.

Restic replaces the old rsync hard-link snapshots. It splits files into
chunks, deduplicates unchanged chunks and compresses stored data. The script's
save, player-activity and stopped-world safeguards remain in front of Restic.

## Deployment and old backups

On September 7, 2026, the old timer was stopped and its 30 plain snapshots
were moved to:

```text
/home/veeti/backups-legacy/servu/
```

They use 2,554,249,216 allocated bytes (about 2.55 GB). Keep them while the
new repository is tested. The fresh Restic repository has no imported history,
which makes it easy to compare its growth with the old format.

The Restic version was deployed and tested on September 7, 2026. Two online
snapshots used 661,983,232 allocated bytes in total. The first added 641.0 MB;
the second added 19.9 MB. `restic check --read-data` passed, exclusions were
verified, and a full 1.221 GiB scratch restore passed Restic's file verification.
The scratch copy was then removed. This is an early comparison only: two new
snapshots and 30 old snapshots do not represent the same history.

## Schedule and status

`minecraft-backup.timer` starts one pass shortly after boot, then 12–18
minutes after the previous pass finishes. Each pass visits all server
folders, including stopped servers. New folders are picked up on the next
pass; no per-server Nix changes are needed.

Copies run one at a time. A retry waits a random 60–180 seconds and lets the
other pending servers run first. One server's failure does not stop the
others, but the service reports failure if any server fails. The entire pass
has a 30-minute limit, including retries.

The script sends private messages to `81133` on the relevant server when an
attempt starts, completes, needs a retry, or fails. Private messages omit the
server name and online/offline label; the system log retains both. Offline
servers and players receive no message. Notification errors do not fail a
backup.

A completion message looks like:

```text
Backup completed in 2.4s (+8.7 MB).
```

The added amount is the increase in allocated filesystem blocks inside that
server's Restic repository from immediately before to immediately after the
backup command. It therefore reflects compressed, deduplicated repository
data plus Restic's new snapshot/index data. Existing chunks reused from older
snapshots do not add space.

This is not logical world growth or an exact long-term change in free disk
space. Restic can store a changed file as a few new chunks rather than a whole
copy, and filesystem block rounding applies. The number is measured before
retention and does not subtract data later removed by pruning. Repository
initialization is also outside the first backup's number.

## Running servers

1. Watch `logs/latest.log` for joins, logouts and save errors.
2. Send `save-off` and wait for its reply. If saving was already off, abort
   without enabling it.
3. Send `save-all flush` and wait for completion (up to 180 seconds).
4. Run Restic against the server directory. Exclude `logs/`, `cache/` and all
   `session.lock` files. The Restic command has a ten-minute limit.
5. Send `list` and wait for the game-thread reply so any logout currently
   saving can finish and reach the log.
6. Enable saving again. If anyone joined or left during the save/backup
   window, forget the unverified Restic snapshot and queue a retry.
7. Accept the snapshot, apply retention and perform due maintenance.

A failed Restic command does not create a completed snapshot. It can leave
unreferenced chunks, which the next daily prune reclaims. If Restic reports a
snapshot but the final activity check fails, the script immediately forgets
that snapshot. If forgetting also fails, the job reports the unverified
snapshot ID in its error; do not restore it.

The activity check does not cover every possible mod write. Online backups
do not freeze gameplay or provide a fully atomic snapshot. Keep occasional
clean, stopped-server backups too.

## Stopped servers

No Java pane in the matching session means an offline attempt. Before
backing up, the script takes POSIX locks on all existing `session.lock` files
inside the server directory. These are the same kind of locks Minecraft uses.
A busy lock means retry, not permission to copy a running world.

Locks stay held during the backup. A startup attempt in that window may fail
with Minecraft's "world already in use" error; try starting it again after
the backup. The script also forgets the new snapshot if a Java pane appears
or world lock files appear/change during the backup. Locks release on success,
failure or process exit.

New server folders without worlds or logs are backed up too. The script does
not create world files. Manual edits and mod writes outside Minecraft's world
locking are not covered by these locks.

## Retention and recovery

Each server has its own Restic repository, lock, `.saving-disabled` marker
and prune marker. A root lock prevents overlapping passes.

Retention keeps:

- Every snapshot from the last 24 hours.
- The newest older snapshot per UTC day, up to seven days old.

Expired snapshots are forgotten each pass. Restic prunes unreferenced data at
most once per UTC day so frequent backups do not trigger a costly repository
rewrite every time.

The script restores saving in `finally`. A persistent marker plus systemd
`ExecStopPost` also handles a killed process. `--resume-saving` is only a
cleanup switch: it checks every backup directory for markers, even if a
source folder was removed. If Minecraft cannot respond, the marker stays and
the service reports failure. The next pass retries recovery before backing up
anything.

Worlds or files stored outside a server directory are not included. Local
backups do not protect against losing the VM's disk.

## Operations after Nix deployment

```sh
sudo systemctl start minecraft-backup.service
sudo systemctl status minecraft-backup.service
systemctl list-timers minecraft-backup.timer
sudo journalctl -u minecraft-backup.service

sudo -u veeti env RESTIC_PASSWORD=minecraft \
  restic -r /home/veeti/backups/servu/repository snapshots
sudo -u veeti env RESTIC_PASSWORD=minecraft \
  restic -r /home/veeti/backups/servu/repository check
```

Restore into a separate directory, never over the live server:

```sh
mkdir -p /home/veeti/restore-check
sudo -u veeti env RESTIC_PASSWORD=minecraft \
  restic -r /home/veeti/backups/servu/repository \
  restore latest --target /home/veeti/restore-check
```

Because the source path is absolute, the restored server will be under:

```text
/home/veeti/restore-check/home/veeti/servers/servu/
```

Stop Minecraft before replacing live files. Copy restored files; do not point
Minecraft at the repository itself.

## Tests

```sh
python3 -B -m unittest discover -s atx/guests/public/minecraft-backup -v
```

Unit tests use a fake Restic process and fake tmux console, plus separate real
processes for POSIX world-lock tests. They cover repository isolation,
initialization and failures; online and offline backups; deduplicated storage
accounting; retention and daily pruning; activity rejection; private
messages; save recovery; and multiple servers. A real Restic backup, full-data
check and verified scratch restore also passed on the VM after deployment.
