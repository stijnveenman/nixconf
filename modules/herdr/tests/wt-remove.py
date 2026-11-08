"""Test post-remove cleanup with a fake Herdr, including a real temporary Git repo."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/wt-remove.sh"


class RemoveHookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / "calls"
        self.data = self.root / "workspaces.json"
        self.herdr = self.root / "herdr"
        self.herdr.write_text("""#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS"
if [ "$1 $2" = 'workspace list' ]; then
  [ "${FAIL_LIST:-0}" = 0 ] || exit 1
  /bin/cat "$WORKSPACES"
fi
""")
        self.herdr.chmod(0o755)
        self.env = os.environ | {"CALLS": str(self.log), "WORKSPACES": str(self.data)}
        self.wrapper = self.root / "hook"
        self.wrapper.write_text(
            f'#!/bin/bash\nherdr="{self.herdr}"\njq="{shutil.which("jq")}"\n'
            + SCRIPT.read_text()
        )
        self.wrapper.chmod(0o755)

    def workspace_data(self, path):
        self.data.write_text(json.dumps({"result": {"workspaces": [
            {"workspace_id": "w-root", "worktree": {"checkout_path": str(path), "is_linked_worktree": False}},
            {"workspace_id": "w-feature", "worktree": {"checkout_path": str(path), "is_linked_worktree": True}},
            {"workspace_id": "w-other", "worktree": {"checkout_path": str(path) + "-other", "is_linked_worktree": True}},
            {"workspace_id": "w-plain", "worktree": None},
        ]}}))

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def run_hook(self, path, **env):
        return subprocess.run([self.wrapper, str(path)], env=self.env | env, capture_output=True)

    def test_exact_linked_workspace_only(self):
        path = self.root / "checkout with spaces"
        self.workspace_data(path)
        self.assertEqual(self.run_hook(path).returncode, 0)
        self.assertEqual(self.calls(), ["workspace list", "workspace close w-feature"])

    def test_recreated_checkout_is_left_alone(self):
        path = self.root / "checkout"
        path.mkdir()
        self.workspace_data(path)
        self.assertEqual(self.run_hook(path).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_no_match_and_server_failure(self):
        path = self.root / "checkout"
        self.workspace_data(self.root / "different")
        self.assertEqual(self.run_hook(path).returncode, 0)
        self.assertEqual(self.calls(), ["workspace list"])
        self.assertNotEqual(self.run_hook(path, FAIL_LIST="1").returncode, 0)
        self.assertNotIn("workspace close", "\n".join(self.calls()))

    def test_worktrunk_post_remove(self):
        repo = self.root / "repo"
        repo.mkdir()
        def git(*args):
            subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)
        git("init", "-b", "main")
        git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-m", "initial")
        checkout = self.root / "feature checkout"
        git("worktree", "add", "-b", "feature", str(checkout))
        # Git/Worktrunk and Herdr report canonical paths (e.g. /private/var on macOS).
        self.workspace_data(checkout.resolve())
        config = self.root / "config.toml"
        config.write_text(f'[post-remove]\nherdr = "{self.wrapper} {{{{ worktree_path }}}}"\n')
        subprocess.run(["wt", "--config", str(config), "-C", str(repo), "remove", "--foreground", "feature"],
                       check=True, env=self.env, capture_output=True)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and "workspace close w-feature" not in self.calls():
            time.sleep(0.05)
        self.assertFalse(checkout.exists())
        self.assertEqual(self.calls(), ["workspace list", "workspace close w-feature"])


if __name__ == "__main__":
    unittest.main()
