import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import backup


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.servers = root / 'servers'
        self.backups = root / 'backups'
        self.servers.mkdir()
        self.backups.mkdir(mode=0o700)
        patch.object(backup, 'SERVERS', self.servers).start()
        patch.object(backup, 'BACKUPS', self.backups).start()
        patch.object(backup, 'STOP_REQUESTED', False).start()
        self.clock = patch.object(backup, 'datetime', wraps=datetime).start()
        self.now = datetime(2026, 9, 7, 12, tzinfo=timezone.utc)
        self.clock.now.return_value = self.now
        self.addCleanup(patch.stopall)
        self.panes = []
        self.saving = {}
        self.pending = {}
        self.sent = []
        self.messages = []
        self.tmux_error = None
        self.on_command = lambda name, command: None
        self.fake_repos = {}
        self.restic_commands = []
        self.restic_fail = {}
        self.restic_bad_backup_json = False
        self.real_run = subprocess.run
        patch.object(backup.subprocess, 'check_output', side_effect=self.pane_state).start()
        patch.object(backup.subprocess, 'run', side_effect=self.run_command).start()
        self.sleep = patch.object(backup.time, 'sleep').start()
        self.job = self.add_server('servu')
        self.server = self.job.path
        self.logfile = self.server / 'logs/latest.log'
        backup.ensure_repository(self.job)

    def add_server(self, name):
        server = backup.Server(name)
        server.backups.mkdir()
        for directory in ('world/players/data', 'world/region', 'logs', 'mods', 'cache'):
            (server.path / directory).mkdir(parents=True, exist_ok=True)
        (server.path / 'logs/latest.log').touch()
        (server.path / 'world/players/data/player.dat').write_bytes(name.encode() * 2048)
        (server.path / 'world/region/region.mca').write_bytes(b'chest' * 2048)
        (server.path / 'world/session.lock').write_bytes(b'lock')
        (server.path / 'mods/mod.jar').write_bytes(b'mod' * 2048)
        (server.path / 'cache/cache').write_bytes(b'cache')
        self.panes.append((name, f'%{len(self.panes) + 1}', 'java', str(server.path)))
        self.saving[name] = True
        return server

    def set_running(self, name, running):
        self.panes = [(n, p, 'java' if running else 'bash', cwd) if n == name else (n, p, c, cwd)
                      for n, p, c, cwd in self.panes]

    def emit(self, message, name='servu'):
        with (self.servers / name / 'logs/latest.log').open('a') as output:
            output.write('[12:00:00] [Server thread/INFO]: ' + message + '\n')

    def pane_state(self, args, **kwargs):
        target = args[args.index('-t') + 1]
        name, _, command, cwd = next(row for row in self.panes if row[1] == target)
        return f'{name}\t{command}\t{cwd}\n'

    def run_command(self, args, **kwargs):
        if args[0] == 'restic':
            return self.run_restic(args, **kwargs)
        if args[0] != 'tmux':
            return self.real_run(args, **kwargs)
        if args[1] == 'list-panes':
            return subprocess.CompletedProcess(args, 1 if self.tmux_error else 0,
                                               '\n'.join('\t'.join(row) for row in self.panes),
                                               self.tmux_error or '')
        target = args[args.index('-t') + 1]
        name = next(row[0] for row in self.panes if row[1] == target)
        if '-l' in args:
            self.pending[target] = args[-1]
        elif args[-1] == 'Enter':
            command = self.pending[target]
            message_prefix = 'tellraw @a '
            if command.startswith(message_prefix):
                component = json.loads(command[len(message_prefix):])
                self.assertEqual(component['color'], 'gray')
                self.assertTrue(component['italic'])
                self.messages.append((name, component['text'], self.saving[name]))
                return subprocess.CompletedProcess(args, 0)
            self.sent.append((name, command))
            self.on_command(name, command)
            if command == 'save-off':
                self.emit('Automatic saving is now disabled' if self.saving[name] else 'Saving is already turned off', name)
                self.saving[name] = False
            elif command == 'save-on':
                self.emit('Automatic saving is now enabled' if not self.saving[name] else 'Saving is already turned on', name)
                self.saving[name] = True
            elif command == 'save-all flush':
                self.emit('Saved the game', name)
            elif command == 'list':
                self.emit('There are 1 of a max of 10 players online: 71680', name)
            else:
                raise AssertionError(command)
        return subprocess.CompletedProcess(args, 0)

    def run_restic(self, args, **kwargs):
        self.assertEqual(kwargs['env']['RESTIC_PASSWORD'], 'minecraft')
        self.assertNotIn('minecraft', args)
        repository = Path(args[args.index('--repo') + 1])
        command = args[3]
        self.restic_commands.append((repository.parent.name, args[3:]))
        exit_code = self.restic_fail.get(command, 0)
        if exit_code and not (command == 'backup' and exit_code == 3):
            return subprocess.CompletedProcess(args, exit_code, '', f'{command} failed')
        state = self.fake_repos.setdefault(repository, {'snapshots': [], 'counter': 0})
        if command == 'init':
            repository.mkdir()
            (repository / 'config').write_text('{}')
            (repository / 'data').mkdir()
            (repository / 'snapshots').mkdir()
            return subprocess.CompletedProcess(args, 0, 'created restic repository\n', '')
        if command == 'backup':
            state['counter'] += 1
            snapshot_id = f'{state["counter"]:064x}'
            source = Path(args[-1])
            blobs = set()
            for root, directories, files in os.walk(source):
                relative_root = Path(root).relative_to(source)
                if relative_root == Path('.'):
                    directories[:] = [name for name in directories if name not in ('logs', 'cache')]
                for name in files:
                    if name == 'session.lock':
                        continue
                    path = Path(root) / name
                    info = path.stat()
                    digest = hashlib.sha256(path.read_bytes() + str(info.st_mode & 0o777).encode()).hexdigest()
                    blobs.add(digest)
                    blob = repository / 'data' / digest
                    if not blob.exists():
                        blob.write_bytes(path.read_bytes() or b'empty')
            tags = [args[args.index('--tag') + 1]]
            snapshot = {
                'id': snapshot_id,
                'short_id': snapshot_id[:8],
                'time': self.clock.now.return_value.isoformat(),
                'paths': [str(source)],
                'tags': tags,
                '_blobs': blobs,
            }
            state['snapshots'].append(snapshot)
            (repository / 'snapshots' / snapshot_id).write_text(json.dumps(snapshot, default=list))
            if self.restic_bad_backup_json:
                stdout = 'not json\n'
            else:
                stdout = json.dumps({'message_type': 'status'}) + '\n' + json.dumps({
                    'message_type': 'summary', 'snapshot_id': snapshot_id,
                }) + '\n'
            stderr = 'some source files could not be read' if exit_code == 3 else ''
            return subprocess.CompletedProcess(args, exit_code, stdout, stderr)
        if command == 'snapshots':
            public = [{key: value for key, value in item.items() if not key.startswith('_')}
                      for item in state['snapshots']]
            return subprocess.CompletedProcess(args, 0, json.dumps(public), '')
        if command == 'forget':
            remove = set(args[4:])
            state['snapshots'] = [item for item in state['snapshots'] if item['id'] not in remove]
            for snapshot_id in remove:
                (repository / 'snapshots' / snapshot_id).unlink(missing_ok=True)
            return subprocess.CompletedProcess(args, 0, '', '')
        if command == 'prune':
            used = set().union(*(item['_blobs'] for item in state['snapshots'])) if state['snapshots'] else set()
            for blob in (repository / 'data').iterdir():
                if blob.name not in used:
                    blob.unlink()
            return subprocess.CompletedProcess(args, 0, '', '')
        raise AssertionError(args)

    def commands(self, name='servu'):
        return [command for target, command in self.sent if target == name]

    def snapshots(self, server=None):
        return backup.restic_snapshots(server or self.job)

    def assert_clean(self, server=None):
        server = server or self.job
        self.assertTrue(self.saving[server.name])
        self.assertFalse(server.marker.exists())

    def test_online_backup_uses_restic_and_restores_saving(self):
        snapshot_id = backup.backup_once(self.job)
        self.assertEqual(self.commands(), ['save-off', 'save-all flush', 'list', 'save-on'])
        self.assertEqual(self.messages[0], ('servu', 'Backup in 5 seconds.', True))
        self.sleep.assert_called_once_with(5)
        self.assertRegex(self.messages[-1][1], r'^Backup completed \(\d+s, \+\d+MB\)$')
        self.assertTrue(self.messages[-1][2])
        self.assertEqual(self.snapshots()[0]['id'], snapshot_id)
        self.assertEqual(self.snapshots()[0]['tags'], ['online'])
        backup_command = next(command for name, command in self.restic_commands if command[0] == 'backup')
        self.assertIn(str(self.server / 'logs'), backup_command)
        self.assertIn(str(self.server / 'cache'), backup_command)
        self.assertIn('**/session.lock', backup_command)
        self.assertNotIn('rsync', [call.args[0][0] for call in backup.subprocess.run.call_args_list])
        self.assert_clean()

    def test_repository_is_initialized_once_with_hardcoded_password(self):
        self.assertTrue((self.job.repository / 'config').is_file())
        backup.ensure_repository(self.job)
        self.assertEqual(
            [command for _, command in self.restic_commands if command[0] == 'init'],
            [['init', '--repository-version', '2']],
        )
        self.assertEqual(backup.RESTIC_PASSWORD, 'minecraft')

    def test_incremental_storage_is_less_for_unchanged_data(self):
        _, first_added = backup.restic_backup(self.job, 'online')
        _, second_added = backup.restic_backup(self.job, 'online')
        self.clock.now.return_value += timedelta(seconds=10)
        (self.server / 'world/region/region.mca').write_bytes(b'new region' * 2048)
        _, changed_added = backup.restic_backup(self.job, 'online')
        self.assertGreater(first_added, second_added)
        self.assertGreater(changed_added, second_added)
        self.assertGreater(backup.repository_bytes(self.job.repository), 0)

    def test_added_storage_is_logged_and_messaged(self):
        with patch.object(backup, 'log') as logged:
            backup.backup_once(self.job)
        message = self.messages[-1][1]
        self.assertIn(', +', message)
        self.assertTrue(any(message in call.args[0] for call in logged.call_args_list))

    def test_bad_restic_backup_json_fails_without_snapshot_acceptance(self):
        self.restic_bad_backup_json = True
        with self.assertRaisesRegex(backup.BackupError, 'invalid JSON'):
            backup.backup_once(self.job)
        # Restic committed in this fake failure mode but did not report its ID;
        # the real script cannot identify and forget such a malformed result.
        self.assertEqual(len(self.snapshots()), 1)
        self.assert_clean()

    def test_restic_failure_restores_saving(self):
        self.restic_fail['backup'] = 1
        with self.assertRaisesRegex(backup.BackupError, 'backup failed'):
            backup.backup_once(self.job)
        self.assertEqual(self.snapshots(), [])
        self.assert_clean()

    def test_partial_online_backup_discards_only_the_incomplete_snapshot(self):
        complete_id, _ = backup.restic_backup(self.job, 'online')
        self.restic_fail['backup'] = 3

        with self.assertRaisesRegex(backup.BackupError, 'some source files could not be read'):
            backup.backup_once(self.job)

        self.assertEqual([snapshot['id'] for snapshot in self.snapshots()], [complete_id])
        self.assertFalse(any('Backup completed' in message for _, message, _ in self.messages))
        self.assert_clean()

    def test_partial_offline_backup_discards_snapshot(self):
        self.set_running('servu', False)
        self.restic_fail['backup'] = 3

        with self.assertRaisesRegex(backup.BackupError, 'some source files could not be read'):
            backup.backup_once(self.job)

        self.assertEqual(self.snapshots(), [])
        self.assertEqual(self.probe_world_lock(), 0)
        self.assert_clean()

    def test_partial_backup_cleanup_failure_reports_snapshot_and_restores_saving(self):
        self.restic_fail['backup'] = 3
        self.restic_fail['forget'] = 1

        with self.assertRaises(backup.BackupError) as failure:
            backup.backup_once(self.job)

        snapshots = self.snapshots()
        self.assertEqual(len(snapshots), 1)
        self.assertIn('some source files could not be read', str(failure.exception))
        self.assertIn(snapshots[0]['id'], str(failure.exception))
        self.assertIn('forget failed', str(failure.exception))
        self.assert_clean()

    def test_logout_during_backup_forgets_snapshot(self):
        original = backup.restic_backup
        def run(*args):
            result = original(*args)
            self.emit('71680 lost connection: Disconnected')
            return result
        with patch.object(backup, 'restic_backup', side_effect=run), self.assertRaises(backup.PlayerActivity):
            backup.backup_once(self.job)
        self.assertEqual(self.snapshots(), [])
        self.assertTrue(any(command[0] == 'forget' for _, command in self.restic_commands))
        self.assert_clean()

    def test_join_during_save_does_not_start_restic(self):
        self.on_command = lambda name, command: self.emit('71680 joined the game') if command == 'save-all flush' else None
        with patch.object(backup, 'restic_backup') as restic_backup, self.assertRaises(backup.PlayerActivity):
            backup.backup_once(self.job)
        restic_backup.assert_not_called()
        self.assert_clean()

    def test_logout_at_final_barrier_forgets_snapshot(self):
        self.on_command = lambda name, command: self.emit('71680 left the game') if command == 'list' else None
        with self.assertRaises(backup.PlayerActivity):
            backup.backup_once(self.job)
        self.assertEqual(self.snapshots(), [])
        self.assert_clean()

    def test_chat_about_logout_does_not_trigger_retry(self):
        self.on_command = lambda name, command: self.emit('<71680> 81133 left the game') if command == 'list' else None
        backup.backup_once(self.job)
        self.assertEqual(len(self.snapshots()), 1)
        self.assert_clean()

    def test_save_error_aborts_and_restores_saving(self):
        self.on_command = lambda name, command: self.emit('Unable to save the game (is there enough disk space?)') if command == 'save-all flush' else None
        with self.assertRaises(backup.BackupError):
            backup.backup_once(self.job)
        self.assertEqual(self.snapshots(), [])
        self.assert_clean()

    def test_already_disabled_saving_is_left_disabled(self):
        self.saving['servu'] = False
        with self.assertRaisesRegex(backup.BackupError, 'already off'):
            backup.backup_once(self.job)
        self.assertFalse(self.saving['servu'])
        self.assertEqual(self.commands(), ['save-off'])
        self.assertFalse(self.job.marker.exists())

    def test_stale_marker_recovers_saving(self):
        self.saving['servu'] = False
        self.job.marker.touch()
        backup.resume_saving(self.job)
        self.assertEqual(self.commands(), ['save-on'])
        self.assert_clean()

    def test_lost_save_off_acknowledgement_still_reenables_saving(self):
        original_command = backup.Console.command
        def command(console, text, replies, timeout=30):
            return original_command(console, text, replies, timeout=0 if text == 'save-off' else timeout)
        with patch.object(backup.Console, 'command', command):
            with self.assertRaisesRegex(backup.BackupError, 'No acknowledgement'):
                backup.backup_once(self.job)
        self.assert_clean()

    def test_partial_and_rotated_logs(self):
        console = backup.Console(self.job)
        self.addCleanup(console.close)
        with self.logfile.open('ab') as output:
            output.write(b'[12:00:00] [Server thread/INFO]: 71680 left')
        self.assertEqual(console.read(), [])
        with self.logfile.open('ab') as output:
            output.write(b' the game\n')
        self.assertEqual(console.read(), ['71680 left the game'])
        self.assertTrue(console.activity)
        self.logfile.rename(self.logfile.with_suffix('.old'))
        self.logfile.touch()
        with self.assertRaisesRegex(backup.RetryBackup, 'changed or was truncated'):
            console.read()

    def test_notification_failure_does_not_fail_backup(self):
        original_send = backup.Console.send
        def send(console, command):
            if command.startswith('tellraw @a '):
                raise backup.BackupError('notification failed')
            return original_send(console, command)
        with patch.object(backup.Console, 'send', send):
            backup.backup_once(self.job)
        self.assertEqual(len(self.snapshots()), 1)
        self.assertEqual(self.messages, [])
        self.assert_clean()

    def test_discovery_includes_directories_not_files_or_symlinks(self):
        (self.servers / 'new-server').mkdir()
        (self.servers / 'notes.txt').touch()
        (self.servers / 'link').symlink_to(self.server, target_is_directory=True)
        self.assertEqual([server.name for server in backup.discover()], ['new-server', 'servu'])

    def test_finds_only_java_in_matching_session_and_directory(self):
        self.panes.insert(0, ('servu', '%8', 'btop', str(self.server)))
        self.assertEqual(backup.find_pane(self.job), '%1')
        self.panes.append(('servu', '%9', 'java', str(self.server)))
        with self.assertRaisesRegex(backup.BackupError, 'More than one'):
            backup.find_pane(self.job)
        self.panes = [('servu', '%1', 'java', '/somewhere/else')]
        with self.assertRaisesRegex(backup.BackupError, 'not '):
            backup.find_pane(self.job)

    def test_no_tmux_server_is_offline_but_permission_error_is_not(self):
        self.tmux_error = 'error connecting to /tmp/tmux-1000/default (No such file or directory)'
        self.assertIsNone(backup.find_pane(self.job))
        self.tmux_error = 'error connecting to /tmp/tmux-1000/default (Permission denied)'
        with self.assertRaises(backup.BackupError):
            backup.find_pane(self.job)

    def test_two_servers_have_separate_repositories_and_commands(self):
        other = self.add_server('other')
        first = backup.attempt(self.job)
        second = backup.attempt(other)
        self.assertNotEqual(self.job.repository, other.repository)
        self.assertEqual(self.snapshots(self.job)[0]['id'], first)
        self.assertEqual(self.snapshots(other)[0]['id'], second)
        for server in (self.job, other):
            self.assertTrue((server.backups / '.lock').exists())
            self.assertEqual(self.commands(server.name), ['save-off', 'save-all flush', 'list', 'save-on'])
            self.assert_clean(server)

    def test_symlinked_backup_or_repository_is_rejected(self):
        other = self.add_server('other')
        self.job.repository.rename(self.job.backups / 'real-repository')
        self.job.repository.symlink_to(self.job.backups / 'real-repository', target_is_directory=True)
        with self.assertRaisesRegex(backup.BackupError, 'symlinked Restic repository'):
            backup.ensure_repository(self.job)
        shutil.rmtree(self.job.repository.parent / 'real-repository')
        self.job.repository.unlink()
        shutil.rmtree(self.job.backups)
        self.job.backups.symlink_to(other.backups, target_is_directory=True)
        with self.assertRaisesRegex(backup.BackupError, 'symlinked backup directory'):
            backup.attempt(self.job)

    def test_retry_does_not_block_other_servers(self):
        self.add_server('zother')
        order = []
        def attempt(server):
            order.append(server.name)
            if len(order) == 1:
                raise backup.PlayerActivity('Player joined or left during the backup')
        with patch.object(backup, 'attempt', side_effect=attempt), \
             patch.object(backup.random, 'randint', return_value=91), \
             patch.object(backup.time, 'sleep') as sleep:
            self.assertFalse(backup.back_up_all())
        self.assertEqual(order, ['servu', 'zother', 'servu'])
        sleep.assert_called_once()
        self.assertGreater(sleep.call_args.args[0], 90)
        self.assertIn('Retrying in 91s.', self.messages[0][1])

    def test_failure_reports_and_continues_other_servers(self):
        self.add_server('zother')
        def attempt(server):
            if server.name == 'servu':
                raise backup.BackupError('backup failed')
        with patch.object(backup, 'attempt', side_effect=attempt) as attempted:
            self.assertTrue(backup.back_up_all())
        self.assertEqual(attempted.call_count, 2)
        self.assertEqual(self.messages, [('servu', 'Backup failed. Check the server log.', True)])

    def test_recovery_continues_after_source_is_missing(self):
        other = self.add_server('zother')
        backup.ensure_repository(other)
        self.set_running('servu', False)
        shutil.rmtree(self.server)
        self.job.marker.touch()
        other.marker.touch()
        self.saving['zother'] = False
        self.assertTrue(backup.recover_all())
        self.assertTrue(self.job.marker.exists())
        self.assert_clean(other)

    def test_resume_only_does_not_start_backups_and_cli_has_no_server_args(self):
        self.job.marker.touch()
        self.saving['servu'] = False
        with patch('sys.argv', ['backup.py', '--resume-saving']), \
             patch.object(backup.signal, 'signal'), patch.object(backup, 'back_up_all') as start:
            self.assertEqual(backup.main(), 0)
        start.assert_not_called()
        self.assert_clean()
        with patch('sys.argv', ['backup.py', '--server', '/wrong']), patch('sys.stderr'):
            with self.assertRaises(SystemExit) as error:
                backup.main()
        self.assertEqual(error.exception.code, 2)

    def probe_world_lock(self):
        code = ('import fcntl, sys\n'
                'with open(sys.argv[1], "r+b") as file:\n'
                ' try: fcntl.lockf(file, fcntl.LOCK_EX | fcntl.LOCK_NB)\n'
                ' except BlockingIOError: sys.exit(7)\n')
        return self.real_run([sys.executable, '-c', code, str(self.server / 'world/session.lock')]).returncode

    def test_offline_backup_holds_world_lock_and_uses_restic(self):
        self.set_running('servu', False)
        original = backup.restic_backup
        def run(*args):
            self.assertEqual(self.probe_world_lock(), 7)
            return original(*args)
        with patch.object(backup, 'restic_backup', side_effect=run):
            snapshot_id = backup.backup_once(self.job)
        self.assertEqual(self.probe_world_lock(), 0)
        self.assertEqual(self.sent, [])
        self.assertEqual(self.messages, [])
        self.assertEqual(self.snapshots()[0]['id'], snapshot_id)
        self.assertEqual(self.snapshots()[0]['tags'], ['offline'])
        self.assert_clean()

    def test_busy_world_lock_prevents_offline_backup(self):
        self.set_running('servu', False)
        code = ('import fcntl, sys\n'
                'with open(sys.argv[1], "r+b") as file:\n'
                ' fcntl.lockf(file, fcntl.LOCK_EX)\n'
                ' print("locked", flush=True)\n'
                ' sys.stdin.readline()\n')
        child = subprocess.Popen([sys.executable, '-c', code, str(self.server / 'world/session.lock')],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'locked')
            with patch.object(backup, 'restic_backup') as run, self.assertRaises(backup.RetryBackup):
                backup.backup_once(self.job)
            run.assert_not_called()
        finally:
            child.communicate('\n', timeout=5)
        self.assert_clean()

    def test_startup_or_new_world_during_offline_backup_discards_snapshot(self):
        for change in ('startup', 'world'):
            with self.subTest(change=change):
                self.set_running('servu', False)
                original = backup.restic_backup
                def run(*args):
                    result = original(*args)
                    if change == 'startup':
                        self.set_running('servu', True)
                    else:
                        (self.server / 'new-world').mkdir(exist_ok=True)
                        (self.server / 'new-world/session.lock').touch()
                    return result
                with patch.object(backup, 'restic_backup', side_effect=run), self.assertRaises(backup.RetryBackup):
                    backup.backup_once(self.job)
                self.assertEqual(self.snapshots(), [])
                if change == 'world':
                    shutil.rmtree(self.server / 'new-world')
                self.assert_clean()

    def test_new_server_without_world_or_log_is_backed_up_offline(self):
        self.set_running('servu', False)
        shutil.rmtree(self.server / 'world')
        shutil.rmtree(self.server / 'logs')
        snapshot_id = backup.backup_once(self.job)
        self.assertEqual(self.snapshots()[0]['id'], snapshot_id)
        self.assertFalse((self.server / 'world').exists())
        self.assert_clean()

    def add_fake_snapshot(self, age):
        self.clock.now.return_value = self.now - age
        snapshot_id, _ = backup.restic_backup(self.job, 'offline')
        return snapshot_id

    def test_retention_keeps_recent_hourly_and_latest_daily_snapshots(self):
        recent = [self.add_fake_snapshot(timedelta(hours=hours)) for hours in (1, 2)]
        hourly = self.add_fake_snapshot(timedelta(hours=3, minutes=10))
        same_hour = self.add_fake_snapshot(timedelta(hours=3, minutes=20))
        other_hour = self.add_fake_snapshot(timedelta(hours=4, minutes=10))
        daily = self.add_fake_snapshot(timedelta(days=2, hours=1))
        earlier = self.add_fake_snapshot(timedelta(days=2, hours=2))
        old = self.add_fake_snapshot(timedelta(days=8))
        self.clock.now.return_value = self.now
        backup.expire_snapshots(self.job, self.now)
        kept = {item['id'] for item in self.snapshots()}
        self.assertEqual(kept, set(recent + [hourly, other_hour, daily]))
        self.assertNotIn(same_hour, kept)
        self.assertNotIn(earlier, kept)
        self.assertNotIn(old, kept)

    def test_prune_runs_at_most_once_per_utc_day(self):
        backup.prune_if_due(self.job, self.now)
        self.assertFalse(any(command[0] == 'prune' for _, command in self.restic_commands))
        self.clock.now.return_value = self.now + timedelta(days=1)
        backup.prune_if_due(self.job, self.clock.now.return_value)
        backup.prune_if_due(self.job, self.clock.now.return_value)
        self.assertEqual(sum(command[0] == 'prune' for _, command in self.restic_commands), 1)
        self.assertEqual(self.job.prune_marker.read_text().strip(), '2026-09-08')


if __name__ == '__main__':
    unittest.main()
