"""Exercise wt-start with fake tools; never create worktrees or launch agents."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/wt-start.sh"
MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == "git":
    if args[0] == "show-ref":
        sys.exit(0 if os.environ.get("EXISTING") else 1)
    sys.exit(0)
if name == "wt":
    if os.environ.get("FAIL_WT"):
        sys.exit(1)
    print(json.dumps({"path": "/tmp/checkouts/feature one"}))
elif args[:2] == ["worktree", "list"]:
    print(json.dumps({"result": {"source": {"repo_root": "/tmp/primary repo"}}}))
elif args[:2] == ["worktree", "open"]:
    print(json.dumps({"result": {"workspace": {"workspace_id": "w1"},
                                 "root_pane": {"pane_id": "w1:p1"}}}))
elif args[:2] == ["pane", "split"]:
    print(json.dumps({"result": {"pane": {"pane_id": "w1:p2"}}}))
elif args[:2] == ["agent", "start"] and os.environ.get("FAIL_START"):
    sys.exit(1)
else:
    print("{}")
'''

with tempfile.TemporaryDirectory(prefix="wt-start-test-") as temp:
    root = Path(temp)
    calls = root / "calls.jsonl"
    env = dict(os.environ, CALLS=str(calls), jq=shutil.which("jq"))
    for name in ("wt", "herdr", "git"):
        mock = root / name
        mock.write_text(MOCK)
        mock.chmod(0o755)
        env[name] = str(mock)

    def run(args, **overrides):
        calls.write_text("")
        result = subprocess.run(
            [shutil.which("bash"), str(SCRIPT), *args],
            env=dict(env, **overrides), capture_output=True, text=True,
        )
        return result, [json.loads(line) for line in calls.read_text().splitlines()]

    prompt = "Fix 'quotes', $HOME and $(touch /tmp/never-run-wt-test)\nsecond line"
    result, log = run(["feature-one", "--base", "origin/main", "-p", prompt])
    assert result.returncode == 0, result.stderr
    switch = next(call for call in log if call[0] == "wt")
    assert switch == ["wt", "switch", "--no-cd", "--format=json", "--create",
                      "--base", "origin/main", "feature-one"]
    opened = next(call for call in log if call[:3] == ["herdr", "worktree", "open"])
    assert opened == ["herdr", "worktree", "open", "--cwd", "/tmp/primary repo",
                      "--path", "/tmp/checkouts/feature one", "--label", "feature-one", "--no-focus"]
    split = next(call for call in log if call[:3] == ["herdr", "pane", "split"])
    assert split == ["herdr", "pane", "split", "w1:p1", "--direction", "right",
                     "--cwd", "/tmp/checkouts/feature one", "--no-focus"]
    assert ["herdr", "agent", "prompt", "pi-w1-p2", prompt] in log
    assert not any("--focus" in call or "focus" in call for call in log)

    prompt_file = root / "prompt with spaces.txt"
    file_prompt = prompt + "\n\n"
    prompt_file.write_text(file_prompt)
    result, log = run(["feature-one", "--prompt-file", str(prompt_file)])
    assert result.returncode == 0, result.stderr
    assert ["herdr", "agent", "prompt", "pi-w1-p2", file_prompt] in log

    empty_file = root / "empty.txt"
    empty_file.write_text("")
    for args in (["feature", "--prompt-file"],
                 ["feature", "--prompt-file", str(root / "missing")],
                 ["feature", "--prompt-file", str(empty_file)],
                 ["feature", "--prompt-file", str(root)],
                 ["feature", "-p", "hello", "--prompt-file", str(prompt_file)],
                 ["feature", "--prompt-file", str(prompt_file), "-p", "hello"]):
        result, log = run(args)
        assert result.returncode != 0, args
        assert not log, log

    result, log = run(["feature-one", "--focus", "-p", "hello"])
    assert result.returncode == 0, result.stderr
    assert log[-1] == ["herdr", "agent", "focus", "pi-w1-p2"]
    assert all("--no-focus" in call for call in log
               if call[:3] in (["herdr", "worktree", "open"], ["herdr", "pane", "split"]))

    result, log = run(["feature-one", "--prompt", "hello"], EXISTING="1")
    assert result.returncode == 0, result.stderr
    assert next(call for call in log if call[0] == "wt") == [
        "wt", "switch", "--no-cd", "--format=json", "feature-one"]

    result, log = run(["feature-one"])
    assert result.returncode == 0, result.stderr
    assert not any(call[:3] == ["herdr", "agent", "prompt"] for call in log)

    for args in ([], ["feature", "--base"], ["feature", "-p"], ["feature", "--bad"],
                 ["feature", "unexpected"]):
        result, log = run(args)
        assert result.returncode != 0, args
        assert not log, log

    result, log = run(["feature", "--base", "pr:123"])
    assert result.returncode == 0, result.stderr
    assert next(call for call in log if call[0] == "wt") == [
        "wt", "switch", "--no-cd", "--format=json", "--create",
        "--base", "pr:123", "feature"]
    assert not any(call[0] == "git" and "pr:123" in call for call in log)

    result, log = run(["feature", "--base", "pr:123"], EXISTING="1")
    assert result.returncode == 0, result.stderr
    assert next(call for call in log if call[0] == "wt") == [
        "wt", "switch", "--no-cd", "--format=json", "--base", "pr:123", "feature"]

    result, log = run(["feature"], FAIL_WT="1")
    assert result.returncode != 0
    assert not any(call[:3] == ["herdr", "worktree", "open"] for call in log)

    result, log = run(["feature", "-p", "hello"], FAIL_START="1")
    assert result.returncode != 0
    assert not any(call[:3] == ["herdr", "agent", "prompt"] for call in log)

print("PASS: creation, base selection, parent nesting, pane layout, prompt quoting, existing branches, argument validation and failures")
