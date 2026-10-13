import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import backup


class MonitoringStatusTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        patcher = patch.object(backup, 'BACKUPS', self.directory)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.server = backup.Server('servu')
        self.server.backups.mkdir()
        self.status = self.server.backups / '.monitoring.json'

    def test_attempt_success_then_failure_preserves_last_success(self):
        with patch.object(backup, 'ensure_repository'), patch.object(backup, 'resume_saving'), \
                patch.object(backup, 'backup_once', return_value='snapshot'), \
                patch.object(backup.time, 'time', return_value=1234):
            self.assertEqual(backup.attempt(self.server), 'snapshot')
        status = json.loads(self.status.read_text())
        self.assertTrue(status['success'])
        self.assertFalse(status['in_progress'])
        self.assertEqual(status['last_success'], 1234)
        with patch.object(backup, 'ensure_repository'), patch.object(backup, 'resume_saving'), \
                patch.object(backup, 'backup_once', side_effect=backup.BackupError('failed')), \
                patch.object(backup.time, 'time', return_value=2345):
            with self.assertRaises(backup.BackupError):
                backup.attempt(self.server)
        status = json.loads(self.status.read_text())
        self.assertFalse(status['success'])
        self.assertFalse(status['in_progress'])
        self.assertEqual(status['last_attempt'], 2345)
        self.assertEqual(status['last_success'], 1234)

    def test_invalid_previous_json_and_write_failure_are_safe(self):
        self.status.write_text('broken')
        backup.record_status(self.server, success=True)
        self.assertTrue(json.loads(self.status.read_text())['success'])
        with patch.object(backup.os, 'replace', side_effect=OSError('disk error')):
            backup.record_status(self.server, success=False)
        self.assertTrue(json.loads(self.status.read_text())['success'])


if __name__ == '__main__':
    unittest.main()
