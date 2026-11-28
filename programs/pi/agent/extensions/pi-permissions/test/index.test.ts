/**
 * End-to-end test of the gate with a fake pi: a parent session with a UI and a
 * pi-subagents child that has none. Needs `@earendil-works/pi-coding-agent`
 * resolvable (see README); skipped otherwise.
 */
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const agentDir = mkdtempSync(join(tmpdir(), "pi-permissions-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
mkdirSync(join(agentDir, "agents"));
writeFileSync(
  join(agentDir, "permissions.json"),
  JSON.stringify({
    permissions: [
      { action: "shell", resource: "*", effect: "ask" },
      { action: "shell", resource: "git *", effect: "allow" },
      { action: "shell", resource: "rm *", effect: "deny" },
      { action: "subagent", resource: "*", effect: "deny" },
      { action: "subagent", resource: "scout", effect: "allow" },
    ],
    agents: { scout: { permissions: [{ action: "edit", resource: "*", effect: "deny" }] } },
  }),
);
writeFileSync(join(agentDir, "agents", "scout.md"), "---\npermission:\n  bash:\n    ls *: allow\n---\nbody\n");

// biome-ignore lint: loaded dynamically
let mod: any;
try {
  mod = await import("../index.ts");
} catch {
  mod = undefined;
}

type Handler = (event: any, ctx: any) => any;

function fakeSession(sessionId: string, hasUI: boolean, answers: string[] = []) {
  const handlers = new Map<string, Handler[]>();
  const bus = new Map<string, ((d: unknown) => void)[]>();
  const prompts: string[] = [];
  const pi = {
    on: (name: string, h: Handler) => handlers.set(name, [...(handlers.get(name) ?? []), h]),
    events: {
      on: (ch: string, h: (d: unknown) => void) => bus.set(ch, [...(bus.get(ch) ?? []), h]),
      emit: (ch: string, d: unknown) => (bus.get(ch) ?? []).forEach((h) => h(d)),
    },
    registerCommand: () => {},
  };
  const ctx = {
    cwd: "/work/proj",
    hasUI,
    isProjectTrusted: () => false,
    sessionManager: { getSessionId: () => sessionId },
    ui: {
      select: async (title: string, options: string[]) => {
        prompts.push(title);
        const a = answers.shift() ?? "Deny";
        return options.find((o) => o.startsWith(a));
      },
      input: async () => "use git instead",
      notify: () => {},
    },
  };
  mod!.default(pi);
  const fire = async (name: string, event: any) => {
    let result: any;
    for (const h of handlers.get(name) ?? []) result = (await h(event, ctx)) ?? result;
    return result;
  };
  return { pi, ctx, fire, prompts };
}

test("parent: rules, prompts and session approvals", { skip: !mod }, async () => {
  const parent = fakeSession("parent-1", true, ["Always allow this session", "Allow once"]);
  await parent.fire("session_start", {});
  const call = (command: string) => parent.fire("tool_call", { toolName: "bash", input: { command } });

  assert.equal(await call("git status && git log"), undefined);
  assert.match((await call("git status; sudo rm -rf x")).reason, /rm -rf x.*denied/);
  assert.equal(await call("npm test"), undefined); // always allow → npm test *
  assert.equal(await call("npm test --watch"), undefined); // no prompt
  assert.equal(parent.prompts.length, 1);
  assert.equal(await call("python3 -c 'x'"), undefined); // Allow once
  assert.match(parent.prompts[1], /python3 -c x.*inline code/s);
  assert.match((await call("make")).reason, /user denied/i);

  assert.match((await parent.fire("tool_call", { toolName: "subagent", input: { subagent_type: "general-purpose" } })).reason, /denied/);
  assert.equal(await parent.fire("tool_call", { toolName: "subagent", input: { subagent_type: "scout" } }), undefined);
});

test("child: own agent rules, asks forwarded to the parent", { skip: !mod }, async () => {
  const parent = fakeSession("parent-2", true, ["Allow once", "Deny with feedback"]);
  await parent.fire("session_start", {});
  // pi-subagents announces the child on the parent's bus before binding it.
  parent.pi.events.emit("subagents:child:spawning", { agentName: "scout", parentSessionId: "parent-2" });
  parent.pi.events.emit("subagents:child:session-created", { sessionId: "child-1", parentSessionId: "parent-2" });

  const child = fakeSession("child-1", false);
  await child.fire("session_start", {});
  const opts = { selectedTools: ["read", "bash", "edit", "write"] };
  await child.fire("before_agent_start", { systemPrompt: '<active_agent name="scout"/>\n\nhi', systemPromptOptions: opts });
  assert.deepEqual(opts.selectedTools, ["read", "bash"]); // edit/write fully denied for scout

  const call = (command: string) => child.fire("tool_call", { toolName: "bash", input: { command } });
  assert.equal(await call("ls -la"), undefined); // frontmatter allow, no prompt
  assert.equal(child.prompts.length + parent.prompts.length, 0);
  assert.equal(await call("cat x"), undefined); // forwarded, parent allowed once
  assert.match(parent.prompts[0], /subagent scout/);
  assert.match((await call("curl x")).reason, /use git instead/);
  assert.equal(child.prompts.length, 0);

  parent.pi.events.emit("subagents:child:disposed", { sessionId: "child-1" });
});

test("no UI and no parent: asks are blocked", { skip: !mod }, async () => {
  const lone = fakeSession("print-1", false);
  await lone.fire("session_start", {});
  assert.match((await lone.fire("tool_call", { toolName: "bash", input: { command: "make" } })).reason, /no interactive UI/);
});
