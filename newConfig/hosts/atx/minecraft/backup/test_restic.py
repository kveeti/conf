import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import backup


@unittest.skipUnless(shutil.which('restic'), 'restic is not installed')
@unittest.skipIf(os.geteuid() == 0, 'root can read files with mode 000')
class ResticIntegrationTests(unittest.TestCase):
    def test_unreadable_file_does_not_leave_an_incomplete_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(backup, 'SERVERS', root / 'servers'), \
                 patch.object(backup, 'BACKUPS', root / 'backups'), \
                 patch.object(backup, 'find_pane', return_value=None), \
                 patch.dict(os.environ, {'RESTIC_CACHE_DIR': str(root / 'cache')}):
                server = backup.Server('test')
                server.path.mkdir(parents=True)
                (server.path / 'world.dat').write_bytes(b'world data')
                backup.ensure_repository(server)
                complete_id = backup.backup_once(server)

                unreadable = server.path / 'unreadable.dat'
                unreadable.write_bytes(b'cannot be backed up')
                unreadable.chmod(0)
                try:
                    with self.assertRaises(backup.IncompleteBackup):
                        backup.backup_once(server)
                finally:
                    unreadable.chmod(0o600)

                snapshots = backup.restic_snapshots(server)
                self.assertEqual([snapshot['id'] for snapshot in snapshots], [complete_id])


if __name__ == '__main__':
    unittest.main()
