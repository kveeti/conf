# Backups and recovery

Each repository uses one password for REST access and encryption. The six legacy
repositories keep their original encryption passwords and IDs. Modi's old file
snapshots were discarded after a verified directory backup; other history stays.
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

The shared backup module requires a `passwordFile` and an absolute
`restoreDirectory` included in `paths`. All active backups restore directories.
Modi dumps MongoDB to `/var/lib/modi-backups/database.archive`; PostgreSQL uses
online logical dumps. Both import the dump after restoring its directory.

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
