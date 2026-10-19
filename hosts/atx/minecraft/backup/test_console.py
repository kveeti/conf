import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import console


class ConsoleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pipe = self.root / 'minecraft-servu.stdin'
        os.mkfifo(self.pipe)
        self.runtime = patch.object(console, 'RUNTIME', self.root)
        self.runtime.start()
        self.addCleanup(self.runtime.stop)

    def open_reader(self):
        reader = os.open(self.pipe, os.O_RDONLY | os.O_NONBLOCK)
        self.addCleanup(os.close, reader)
        return reader

    def test_command_reaches_pipe_as_one_complete_line(self):
        reader = self.open_reader()
        with patch.object(console, 'server_pid', return_value=42):
            console.send_command('servu', 'save-all flush', expected_pid=42)
        self.assertEqual(os.read(reader, 4096), b'save-all flush\n')

    def test_no_reader_fails_instead_of_waiting_forever(self):
        with patch.object(console, 'server_pid', return_value=42):
            with self.assertRaises(OSError):
                console.send_command('servu', 'list')

    def test_full_pipe_fails_instead_of_waiting_forever(self):
        self.open_reader()
        writer = os.open(self.pipe, os.O_WRONLY | os.O_NONBLOCK)
        self.addCleanup(os.close, writer)
        with self.assertRaises(BlockingIOError):
            while True:
                os.write(writer, b'x' * 4096)
        with patch.object(console, 'server_pid', return_value=42):
            with self.assertRaises(BlockingIOError):
                console.send_command('servu', 'list')

    def test_restarted_or_stopped_server_gets_no_command(self):
        reader = self.open_reader()
        for pid in (None, 43):
            with self.subTest(pid=pid), patch.object(console, 'server_pid', return_value=pid):
                with self.assertRaises(RuntimeError):
                    console.send_command('servu', 'save-off', expected_pid=42)
        self.assertEqual(os.read(reader, 4096), b'')

    def test_rejects_multiple_commands_and_oversized_writes(self):
        reader = self.open_reader()
        for command in ('', 'list\nstop', 'list\rstop', 'list\0stop', 'x' * 65536):
            with self.subTest(command=command[:20]), patch.object(console, 'server_pid', return_value=42):
                with self.assertRaises(RuntimeError):
                    console.send_command('servu', command)
        self.assertEqual(os.read(reader, 4096), b'')

    def test_active_service_returns_pid(self):
        result = subprocess.CompletedProcess([], 0, 'LoadState=loaded\nActiveState=active\nMainPID=42\n')
        with patch.object(console.subprocess, 'run', return_value=result):
            self.assertEqual(console.server_pid('servu'), 42)

    def test_offline_and_transitioning_service_states(self):
        for state in ('inactive', 'failed', 'activating', 'deactivating'):
            result = subprocess.CompletedProcess([], 0, f'LoadState=loaded\nActiveState={state}\nMainPID=0\n')
            with self.subTest(state=state), patch.object(console.subprocess, 'run', return_value=result):
                if state in ('inactive', 'failed'):
                    self.assertIsNone(console.server_pid('servu'))
                else:
                    with self.assertRaises(RuntimeError):
                        console.server_pid('servu')

    def test_systemctl_failure_does_not_look_like_an_offline_server(self):
        with patch.object(console.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'systemctl')):
            with self.assertRaises(subprocess.CalledProcessError):
                console.server_pid('servu')


if __name__ == '__main__':
    unittest.main()
