# Minecraft servu

The NixOS config runs the existing Fabric server in `/home/veeti/servers/servu`
as `veeti`, with Java 25 and a 4 GB heap. It does not manage mods, world files,
or `server.properties`. The launcher filename lives in `server.nix`; update it
when upgrading Fabric.

## Console

Run these over SSH as `veeti`:

```sh
mc-command "list"
mc-command "save-all flush"
journalctl -fu minecraft-servu
```

`mc-command` sends one command through `/run/minecraft-servu.stdin`. Replies
appear in the journal and `servers/servu/logs/latest.log`. The pipe does not
open a network port. Commands fail promptly if the service is stopped or the
pipe is full.

```sh
sudo systemctl restart minecraft-servu
sudo systemctl stop minecraft-servu
```

Stopping the service sends SIGINT so Minecraft saves and shuts down. systemd
allows up to three minutes before forcing it to exit. It starts at boot and
restarts after a crash.

## Switch from tmux

Do not deploy this config while the tmux server is still running.

1. Stop the backup timer and wait for any active backup to finish. If stopping
   the backup service instead, check its recovery output to confirm saving is on.
2. In the existing Minecraft console, run `save-on`, then `stop`. Wait for Java
   to exit and the world to finish saving.
3. Deploy the NixOS config. Start `minecraft-servu.service` and
   `minecraft-backup.timer` if deployment did not start them.
4. Check the service journal, run `mc-command "list"`, and run
   `sudo systemctl start minecraft-backup.service` to check a full backup.

Backups now find the server through systemd and use the pipe. They still wait
for Minecraft's save confirmations in `logs/latest.log`. An offline backup
still requires the world's session locks. Do not run the server in tmux after
switching.

## Tests

```sh
cd hosts/atx/minecraft/backup
nix shell nixpkgs#python3 nixpkgs#restic -c python3 -B -m unittest discover
```
