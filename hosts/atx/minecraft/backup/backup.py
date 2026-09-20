#!/usr/bin/env python3
"""Back up every Minecraft server under /home/veeti/servers with Restic."""

import argparse
from contextlib import contextmanager, ExitStack
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import fcntl
import heapq
import json
import os
from pathlib import Path
import random
import re
import signal
import stat
import subprocess
import time

SERVERS = Path('/home/veeti/servers')
BACKUPS = Path('/home/veeti/backups')
RESTIC_PASSWORD = 'minecraft'
STOP_REQUESTED = False
MESSAGE = re.compile(r'^\[\d{2}:\d{2}:\d{2}\] \[Server thread/INFO\]: (.*)$')
ACTIVITY = re.compile(
    r'^[A-Za-z0-9_]{1,16}(?: (?:joined the game|left the game)$| lost connection:|\[.*\] logged in with entity id )'
)


class BackupError(Exception):
    pass


class IncompleteBackup(BackupError):
    def __init__(self, message, snapshot_id):
        super().__init__(message)
        self.snapshot_id = snapshot_id


class RetryBackup(BackupError):
    pass


class PlayerActivity(RetryBackup):
    pass


class Interrupted(BackupError):
    pass


def log(message):
    print(message, flush=True)


@dataclass(frozen=True)
class Server:
    name: str

    @property
    def path(self):
        return SERVERS / self.name

    @property
    def backups(self):
        return BACKUPS / self.name

    @property
    def repository(self):
        return self.backups / 'repository'

    @property
    def marker(self):
        return self.backups / '.saving-disabled'

    @property
    def prune_marker(self):
        return self.backups / '.last-prune'

    def log(self, message):
        log(f'[{self.name}] {message}')


def discover():
    return [Server(path.name) for path in sorted(SERVERS.iterdir())
            if path.is_dir() and not path.is_symlink()]


def find_pane(server):
    """Select the sole Java pane in the matching session, not an arbitrary pane."""
    result = subprocess.run(
        ['tmux', 'list-panes', '-a', '-F',
         '#{session_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}'],
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode:
        if ('no server running on ' in result.stderr
                or '(No such file or directory)' in result.stderr
                or result.stderr.strip() == 'no sessions'):
            return None
        raise BackupError('Cannot inspect tmux: ' + result.stderr.strip())
    panes = []
    for line in result.stdout.splitlines():
        session, pane, command, cwd = line.split('\t', 3)
        if session != server.name or command != 'java':
            continue
        if Path(cwd).resolve() != server.path.resolve():
            raise BackupError(f'Java in session {server.name} is running from {cwd}, not {server.path}')
        panes.append(pane)
    if len(panes) > 1:
        raise BackupError(f'More than one Java pane in session {server.name}; refusing to guess')
    return panes[0] if panes else None


class Console:
    def __init__(self, server, pane=None):
        self.server = server
        self.pane = pane or find_pane(server)
        if self.pane is None:
            raise BackupError('No Java pane in the matching tmux session')
        self.check_pane()
        self.path = server.path / 'logs/latest.log'
        self.file = self.path.open('rb')
        self.file.seek(0, os.SEEK_END)
        info = os.fstat(self.file.fileno())
        self.identity = (info.st_dev, info.st_ino)
        self.buffer = b''
        self.activity = False

    def close(self):
        self.file.close()

    def read(self):
        info = self.path.stat()
        if (info.st_dev, info.st_ino) != self.identity or info.st_size < self.file.tell():
            raise BackupError('Server log changed or was truncated; refusing the backup')
        messages = []
        while data := self.file.read(65536):
            self.buffer += data
            lines = self.buffer.split(b'\n')
            self.buffer = lines.pop()
            for line in lines:
                text = line.decode('utf-8', errors='replace').rstrip('\r')
                match = MESSAGE.match(text)
                if match:
                    message = match[1]
                    self.activity |= bool(ACTIVITY.search(message))
                    messages.append(message)
                if re.search(r'Unable to save the game|Failed to save (player|chunk)|Failed to store chunk', text):
                    raise BackupError('Minecraft reported a save error: ' + text)
        return messages

    def check_pane(self):
        state = subprocess.check_output(
            ['tmux', 'display-message', '-p', '-t', self.pane,
             '#{session_name}\t#{pane_current_command}\t#{pane_current_path}'],
            text=True, timeout=5,
        ).strip().split('\t', 2)
        if (len(state) != 3 or state[0] != self.server.name or state[1] != 'java'
                or Path(state[2]).resolve() != self.server.path.resolve()):
            raise BackupError(f'{self.pane} is no longer running this server; refusing to type into it')

    def send(self, command):
        self.check_pane()
        subprocess.run(['tmux', 'send-keys', '-t', self.pane, '-l', '--', command], check=True, timeout=5)
        subprocess.run(['tmux', 'send-keys', '-t', self.pane, 'Enter'], check=True, timeout=5)

    def command(self, command, replies, timeout=30):
        self.read()
        self.send(command)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for message in self.read():
                if any(message.startswith(reply) for reply in replies):
                    return message
            time.sleep(0.1)
        raise BackupError(f'No acknowledgement for {command!r} within {timeout}s')


def notify(server, message):
    """Best-effort PM; an offline server/player must not block a backup."""
    try:
        pane = find_pane(server)
        if pane is None:
            return
        console = Console(server, pane)
        try:
            text = ' '.join(message.splitlines())
            console.send(f'execute if entity @a[name=81133] run tell 81133 {text}')
        finally:
            console.close()
    except Interrupted:
        raise
    except (BackupError, OSError, subprocess.SubprocessError) as error:
        server.log(f'Could not send backup status: {error}')


def resume_saving(server):
    if not server.marker.exists():
        return
    console = Console(server)
    try:
        console.command('save-on', ('Automatic saving is now enabled', 'Saving is already turned on'))
        server.marker.unlink()
        server.log('Automatic saving enabled')
    finally:
        console.close()


def restic(server, arguments, timeout=600, json_output=False):
    environment = os.environ.copy()
    environment['RESTIC_PASSWORD'] = RESTIC_PASSWORD
    result = subprocess.run(
        ['restic', '--repo', str(server.repository), *arguments],
        capture_output=True, text=True, env=environment, timeout=timeout,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or f'exit status {result.returncode}'
        message = f'Restic {arguments[0]} failed: {detail[-2000:]}'
        if arguments[0] == 'backup' and result.returncode == 3:
            raise IncompleteBackup(message, backup_snapshot_id(result.stdout))
        raise BackupError(message)
    if not json_output:
        return result.stdout
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise BackupError(f'Restic {arguments[0]} returned invalid JSON') from error


def ensure_repository(server):
    if server.backups.is_symlink():
        raise BackupError(f'Refusing a symlinked backup directory: {server.backups}')
    server.backups.mkdir(parents=True, exist_ok=True, mode=0o700)
    if server.repository.is_symlink():
        raise BackupError(f'Refusing a symlinked Restic repository: {server.repository}')
    if server.repository.exists():
        if not server.repository.is_dir() or not (server.repository / 'config').is_file():
            raise BackupError(f'Invalid Restic repository: {server.repository}')
        return
    restic(server, ['init', '--repository-version', '2'], timeout=60)
    server.prune_marker.write_text(datetime.now(timezone.utc).date().isoformat() + '\n')


def repository_bytes(repository):
    """Allocated bytes in regular repository files; symlinks are not followed."""
    def fail(error):
        raise error

    total = 0
    for root, _, files in os.walk(repository, onerror=fail):
        for name in files:
            info = (Path(root) / name).lstat()
            if stat.S_ISREG(info.st_mode):
                total += info.st_blocks * 512
    return total


def backup_snapshot_id(output):
    summary = None
    for line in output.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError as error:
            raise BackupError('Restic backup returned invalid JSON') from error
        if message.get('message_type') == 'summary':
            summary = message
    if not summary or not summary.get('snapshot_id'):
        raise BackupError('Restic backup did not report a snapshot ID')
    return summary['snapshot_id']


def restic_backup(server, mode):
    before = repository_bytes(server.repository)
    output = restic(server, [
        'backup', '--json', '--tag', mode,
        '--exclude', str(server.path / 'logs'),
        '--exclude', str(server.path / 'cache'),
        '--exclude', '**/session.lock',
        str(server.path),
    ])
    snapshot_id = backup_snapshot_id(output)
    added_bytes = max(0, repository_bytes(server.repository) - before)
    return snapshot_id, added_bytes


def restic_snapshots(server):
    snapshots = restic(server, ['snapshots', '--json'], timeout=60, json_output=True)
    if not isinstance(snapshots, list):
        raise BackupError('Restic snapshots returned unexpected JSON')
    return snapshots


def parse_restic_time(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)


def expire_snapshots(server, now):
    keep_hours = set()
    keep_days = set()
    remove = []
    ordered = sorted(restic_snapshots(server), key=lambda item: parse_restic_time(item['time']), reverse=True)
    for snapshot in ordered:
        timestamp = parse_restic_time(snapshot['time'])
        if timestamp >= now - timedelta(hours=3):
            continue
        if timestamp >= now - timedelta(hours=48):
            hour = timestamp.replace(minute=0, second=0, microsecond=0)
            if hour not in keep_hours:
                keep_hours.add(hour)
                continue
        elif timestamp >= now - timedelta(days=7):
            day = timestamp.date()
            if day not in keep_days:
                keep_days.add(day)
                continue
        remove.append(snapshot['id'])
    if remove:
        restic(server, ['forget', *remove], timeout=300)
        server.log(f'Forgot {len(remove)} expired Restic snapshot(s)')


def prune_if_due(server, now):
    today = now.date().isoformat()
    try:
        last_prune = server.prune_marker.read_text().strip()
    except FileNotFoundError:
        last_prune = ''
    if last_prune == today:
        return
    restic(server, ['prune'], timeout=900)
    temporary = server.prune_marker.with_suffix('.new')
    temporary.write_text(today + '\n')
    os.replace(temporary, server.prune_marker)
    server.log('Pruned unreferenced Restic data')


def forget_snapshot(server, snapshot_id):
    restic(server, ['forget', snapshot_id], timeout=300)
    server.log(f'Discarded Restic snapshot {snapshot_id[:12]}')


@contextmanager
def locked_worlds(server):
    """Minecraft uses POSIX file locks, not flock, on its session.lock files."""
    with ExitStack() as stack:
        identities = {}
        for path in sorted(server.path.rglob('session.lock')):
            if path.is_symlink():
                raise BackupError(f'Refusing a symlinked world lock: {path}')
            file = stack.enter_context(path.open('r+b'))
            try:
                fcntl.lockf(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RetryBackup('World is in use; cannot take an offline backup') from error
            info = os.fstat(file.fileno())
            identities[path] = (info.st_dev, info.st_ino)
        if find_pane(server) is not None:
            raise RetryBackup('Server started before the offline backup')

        def validate():
            current = {path: (path.stat().st_dev, path.stat().st_ino)
                       for path in server.path.rglob('session.lock')}
            if current != identities or find_pane(server) is not None:
                raise RetryBackup('Server or world changed during the offline backup')

        yield validate


def backup_once(server):
    console = None
    snapshot_id = None
    error = None
    started_at = time.monotonic()
    try:
        pane = find_pane(server)
        if pane is not None:
            console = Console(server, pane)  # Watch before the first save command.
        mode = 'online' if console else 'offline'
        server.log(f'Backup starting ({mode})')
        notify(server, 'Backup starting.')
        if console:
            # ExecStopPost uses this marker even after SIGKILL/OOM.
            server.marker.touch(mode=0o600)
            reply = console.command('save-off', ('Automatic saving is now disabled', 'Saving is already turned off'))
            if reply == 'Saving is already turned off':
                server.marker.unlink()
                raise BackupError('Saving was already off; leaving it off and not making a backup')
            console.command('save-all flush', ('Saved the game',), timeout=180)
            if console.activity:
                raise PlayerActivity('Player joined or left during the save')
            snapshot_id, added_bytes = restic_backup(server, mode)
            # A game-thread reply lets a logout finish and reach the log.
            console.command('list', ('There are ',))
            if console.activity:
                raise PlayerActivity('Player joined or left during the backup')
        else:
            with locked_worlds(server) as validate:
                snapshot_id, added_bytes = restic_backup(server, mode)
                validate()
    except Exception as caught:
        error = caught
        if isinstance(caught, IncompleteBackup):
            snapshot_id = caught.snapshot_id
    finally:
        if console:
            console.close()
        try:
            resume_saving(server)
        except Exception as caught:
            if error is None:
                error = caught
            else:
                server.log(f'Also failed to restore saving: {caught}')
    if error is not None:
        if snapshot_id is not None:
            try:
                forget_snapshot(server, snapshot_id)
            except Exception as discard_error:
                raise BackupError(
                    f'{error}; also failed to discard unverified snapshot {snapshot_id}: {discard_error}'
                ) from error
        raise error

    completed = f'Backup completed in {time.monotonic() - started_at:.1f}s (+{added_bytes / 1_000_000:.1f} MB).'
    server.log(f'{completed} Restic snapshot: {snapshot_id[:12]}')
    notify(server, completed)
    expire_snapshots(server, datetime.now(timezone.utc))
    prune_if_due(server, datetime.now(timezone.utc))
    return snapshot_id


def attempt(server):
    ensure_repository(server)
    with (server.backups / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            server.log('Another backup or cleanup is running; skipping')
            return
        resume_saving(server)
        return backup_once(server)


def report_failure(server, error):
    server.log(f'BACKUP FAILED: {error}')
    if server.marker.exists():
        notify(server, 'Backup failed. Could not confirm saving is enabled; check the server log.')
    else:
        notify(server, 'Backup failed. Check the server log.')


def recover_all():
    """Include markers whose source directory was removed or renamed."""
    failed = False
    for path in sorted(BACKUPS.iterdir()):
        if path.is_symlink() or not path.is_dir():
            continue
        server = Server(path.name)
        try:
            resume_saving(server)
        except Interrupted:
            raise
        except (BackupError, OSError, subprocess.SubprocessError) as error:
            report_failure(server, error)
            failed = True
    return failed


def back_up_all():
    failed = recover_all()
    pending = [(0, server.name) for server in discover()]
    heapq.heapify(pending)
    while pending and not STOP_REQUESTED:
        due, name = heapq.heappop(pending)
        delay = due - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        server = Server(name)
        try:
            attempt(server)
        except Interrupted as error:
            report_failure(server, error)
            raise
        except RetryBackup as error:
            delay = random.randint(60, 180)
            server.log(f'{error}; discarded the snapshot. Retrying in {delay}s.')
            notify(server, f'Backup discarded: {error}. Retrying in {delay}s.')
            heapq.heappush(pending, (time.monotonic() + delay, name))
        except (BackupError, OSError, subprocess.SubprocessError) as error:
            report_failure(server, error)
            failed = True
    if STOP_REQUESTED:
        raise Interrupted('Backup job interrupted')
    return failed


def interrupted(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True
    raise Interrupted(f'Interrupted by signal {signum}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume-saving', action='store_true', help='Only recover saving after an interrupted job')
    args = parser.parse_args()
    os.umask(0o077)
    BACKUPS.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Serialize whole passes, including recovery after a killed service.
    with (BACKUPS / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log('Another backup pass or cleanup is running; skipping')
            return 0
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
        failed = recover_all() if args.resume_saving else back_up_all()
        return 1 if failed else 0


def run():
    try:
        return main()
    except (BackupError, OSError, subprocess.SubprocessError) as error:
        log(f'BACKUP JOB FAILED: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(run())
