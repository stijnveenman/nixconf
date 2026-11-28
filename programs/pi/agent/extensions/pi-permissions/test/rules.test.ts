import assert from "node:assert/strict";
import { test } from "node:test";
import { checksFor } from "../checks.ts";
import { alwaysPattern, DEFAULT_RULES, decide, isFullyDenied, parseRules, type Rule, wildcardMatch } from "../rules.ts";

const r = (action: string, resource: string, effect: Rule["effect"]): Rule => ({ action, resource, effect });

test("wildcards", () => {
  assert.ok(wildcardMatch("git *", "git status --short"));
  assert.ok(wildcardMatch("git status *", "git status"));
  assert.ok(!wildcardMatch("git status *", "git statusx"));
  assert.ok(wildcardMatch("*.env", "src/.env"));
  assert.ok(!wildcardMatch("*.env", ".env.local"));
  assert.ok(wildcardMatch("/tmp/*", "/tmp"));
  assert.ok(wildcardMatch("/tmp/*", "/tmp/a/b"));
  assert.ok(!wildcardMatch("/tmp/*", "/tmpx"));
  assert.ok(wildcardMatch("fil?.txt", "file.txt"));
  assert.ok(wildcardMatch("a.b(c)", "a.b(c)"));
  assert.ok(wildcardMatch("mcp__*", "mcp__docs__search"));
});

test("last match wins, no match asks", () => {
  const rules = [r("shell", "*", "ask"), r("shell", "git *", "allow"), r("shell", "git push *", "deny")];
  assert.equal(decide("shell", [{ value: "git status" }], rules, []).effect, "allow");
  assert.equal(decide("shell", [{ value: "git push origin" }], rules, []).effect, "deny");
  assert.equal(decide("shell", [{ value: "ls" }], rules, []).effect, "ask");
  assert.equal(decide("edit", [{ value: "x" }], rules, []).effect, "ask");
});

test("deny on any resource wins and approvals never override it", () => {
  const rules = [r("*", "*", "allow"), r("shell", "rm *", "deny")];
  const approvals = [r("shell", "rm *", "allow")];
  const d = decide("shell", [{ value: "ls" }, { value: "rm -rf x" }], rules, approvals);
  assert.equal(d.effect, "deny");
  assert.equal(d.resources[0].value, "rm -rf x");
});

test("approvals turn asks into allows", () => {
  const rules = [r("shell", "*", "ask")];
  assert.equal(decide("shell", [{ value: "npm test" }], rules, [r("shell", "npm test *", "allow")]).effect, "allow");
});

test("opaque commands are not covered by catch-all allows", () => {
  const res = [{ value: "python3 -c x", opaque: true }];
  assert.equal(decide("shell", res, DEFAULT_RULES, []).effect, "ask");
  assert.equal(decide("shell", res, [...DEFAULT_RULES, r("shell", "python3 *", "allow")], []).effect, "allow");
});

test("fully denied tools", () => {
  assert.ok(isFullyDenied([r("*", "*", "allow"), r("edit", "*", "deny")], "edit"));
  assert.ok(!isFullyDenied([r("edit", "*", "deny"), r("edit", "docs/*", "allow")], "edit"));
  assert.ok(isFullyDenied([r("edit", "docs/*", "allow"), r("edit", "*", "deny")], "edit"));
  assert.ok(!isFullyDenied([r("*", "*", "deny"), r("*", "*", "allow")], "edit"));
});

test("parses v1 and v2 config shapes", () => {
  const errors: string[] = [];
  assert.deepEqual(
    parseRules({ bash: { "*": "ask", "git *": "allow" }, task: "deny", write: "ask" }, "t", errors).map(({ action, resource, effect }) => [action, resource, effect]),
    [["shell", "*", "ask"], ["shell", "git *", "allow"], ["subagent", "*", "deny"], ["edit", "*", "ask"]],
  );
  assert.deepEqual(
    parseRules([{ action: "bash", resource: "ls *", effect: "allow" }, { action: "read" }], "t", errors).map((x) => x.action),
    ["shell"],
  );
  assert.equal(errors.length, 1);
  assert.deepEqual(parseRules("deny", "t")[0], { action: "*", resource: "*", effect: "deny", source: "t" });
});

test("always patterns use an arity table", () => {
  assert.equal(alwaysPattern(["git", "status", "--short"]), "git status *");
  assert.equal(alwaysPattern(["git", "-C", "x", "log"]), "git *");
  assert.equal(alwaysPattern(["npm", "run", "build"]), "npm run *");
  assert.equal(alwaysPattern(["ls", "-la"]), "ls *");
  assert.equal(alwaysPattern(["gh", "pr", "view", "1"]), "gh pr view *");
});

test("tool calls become checks", () => {
  const cwd = "/home/u/proj";
  assert.deepEqual(checksFor("read", { path: "src/a.ts" }, cwd), [{ action: "read", resources: [{ value: "src/a.ts" }], patterns: ["src/a.ts"] }]);
  const ext = checksFor("edit", { path: "/etc/hosts" }, cwd);
  assert.equal(ext[0].action, "external_directory");
  assert.equal(ext[0].resources[0].value, "/etc");
  assert.deepEqual(ext[1].resources, [{ value: "/etc/hosts" }]);
  const sh = checksFor("bash", { command: "cd /var && sudo rm x" }, cwd);
  assert.equal(sh[0].action, "external_directory");
  assert.deepEqual(sh[1].resources.map((x) => x.value), ["cd /var", "sudo rm x", "rm x"]);
  assert.deepEqual(sh[1].patterns, ["cd *", "sudo *", "rm *"]);
  assert.deepEqual(checksFor("subagent", { subagent_type: "Explore" }, cwd)[0].resources, [{ value: "Explore" }]);
  assert.equal(checksFor("codemode", {}, cwd)[0].action, "execute");
  assert.equal(checksFor("mcp__docs__search", {}, cwd)[0].action, "mcp__docs__search");
});
