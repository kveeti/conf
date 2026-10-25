# Backups and recovery

Each repository uses one password for REST access and encryption. The six legacy
repositories keep their original encryption passwords, IDs, and snapshot history.
HA and Zigbee still share the `ha` repository, with separate snapshot tags.

Recovery is manual:

- On worker: `sudo restore-<service> [snapshot-id]`, including `restore-modi`.
- In the HA guest: `sudo restore-hass [snapshot-id]` or
  `sudo restore-zigbee2mqtt [snapshot-id]`.
- The snapshot defaults to `latest`.

The commands stop the app, restore its files, run any database import, and start
it only on success. A failure stops the command; there is no rollback. Directory
restores keep files which are absent from the snapshot. Nothing restores data
on service startup.

The shared backup module requires a `passwordFile` and an absolute `restorePath`
included in `paths`. The restore path can be a file, such as Modi's MongoDB
archive, or a directory. PostgreSQL backups use online logical dumps and explicit
restore commands.

## Retired backups

`auth`, `authentik`, `bm`, and `internal` remain on ATX. No active app writes to
these repositories. This cleanup does not delete their backups or change their
retention rules. Revisit their lifetime after 90 days; deletion needs a separate
decision.

Retired snapshots keep their original paths and dump formats. Restore them into
a private scratch directory before importing anything. Do not use a current
app's restore command for an old app's snapshot.

The inactive `hosts/atx/internal.nix` and `hosts/atx/internal/` configs remain as
historical references. Their old backup options require the matching shared
modules from Git history; they do not define active restore jobs.
