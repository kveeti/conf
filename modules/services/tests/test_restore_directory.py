import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "restore-path.sh"


@unittest.skipUnless(os.geteuid() == 0, "Restore commands require root")
class RestoreDirectoryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.payload = self.state / "item"
        self.payload.write_text("backed-up state")
        self.password = self.root / "password"
        self.password.write_text("test-only password")
        self.calls = self.root / "hook-calls"
        self.environment = os.environ | {
            "RESTIC_REPOSITORY": str(self.root / "repository"),
            "RESTIC_PASSWORD_FILE": str(self.password),
            "RESTIC_CACHE_DIR": str(self.root / "cache"),
        }
        self.restic("init")
        self.restic("backup", "--tag", "test-app", str(self.state))
        self.snapshot = json.loads(self.restic("snapshots", "--json").stdout)[0]["id"]
        self.payload.write_text("current state")

    def restic(self, *arguments):
        return subprocess.run(
            ["restic", *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
            check=True,
        )

    def restore(self, *arguments, pre_script=None, post_script=None, restore_path=None):
        settings = {
            "restoreName": "test-app",
            "restorePath": str(restore_path or self.state),
            "restoreLock": str(self.root / "lock"),
            "restoreRepository": self.environment["RESTIC_REPOSITORY"],
            "restoreUsername": "test-app",
            "restorePasswordFile": str(self.password),
        }
        setup = "\n".join(f"{key}={shlex.quote(value)}" for key, value in settings.items())
        calls = shlex.quote(str(self.calls))
        payload = shlex.quote(str(self.payload))
        if pre_script is None:
            pre_script = f'printf "pre:" >> {calls}; cat {payload} >> {calls}; echo >> {calls}'
        if post_script is None:
            post_script = f'printf "post:" >> {calls}; cat {payload} >> {calls}; echo >> {calls}'
        setup += '\nrestoreTagArgs=(--tag test-app)\n'
        setup += f"preRestore() {{\n{pre_script}\n:;\n}}\n"
        setup += f"postRestore() {{\n{post_script}\n:;\n}}\n"
        setup += f"source {shlex.quote(str(SCRIPT))}"
        return subprocess.run(
            ["bash", "-c", setup, "restore-test", *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
        )

    def test_latest_restores_between_hooks(self):
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.payload.read_text(), "backed-up state")
        self.assertEqual(
            self.calls.read_text().splitlines(),
            ["pre:current state", "post:backed-up state"],
        )

    def test_explicit_snapshot_restores_older_state(self):
        self.restic("backup", "--tag", "test-app", str(self.state))
        result = self.restore(self.snapshot)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.payload.read_text(), "backed-up state")

    def test_file_restore_selects_snapshots_backed_up_by_file_path(self):
        self.restic("backup", "--tag", "test-app", str(self.payload))
        self.payload.write_text("newer state")
        result = self.restore(restore_path=self.payload)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.payload.read_text(), "current state")

    def test_in_place_restore_keeps_files_absent_from_snapshot(self):
        extra = self.state / "extra"
        extra.write_text("not backed up")
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(extra.read_text(), "not backed up")

    def test_failed_pre_hook_stops_before_restore(self):
        result = self.restore(pre_script="false")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.payload.read_text(), "current state")
        self.assertFalse(self.calls.exists())

    def test_failed_restore_skips_post_hook(self):
        for pack in (self.root / "repository" / "data").glob("*/*"):
            pack.unlink()
        result = self.restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines(), ["pre:current state"])

    def test_failed_post_hook_returns_failure(self):
        result = self.restore(post_script="false")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.payload.read_text(), "backed-up state")


if __name__ == "__main__":
    unittest.main()
