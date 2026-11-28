# pi-permissions

opencode v2-style permissions for pi, with support for
[`@gotgenes/pi-subagents`](https://github.com/gotgenes/pi-packages/tree/main/packages/pi-subagents).

Every tool call is checked against one flat, ordered list of rules. Each rule
is `{ "action", "resource", "effect" }` with effect `allow`, `ask` or `deny`.
The **last matching rule wins**, and a call that matches nothing asks.

## Configuration

Rules are read, in this order, from:

1. opencode's defaults: `* * → allow`, `read *.env` and `read *.env.*` → ask,
   `read *.env.example` → allow (set `"defaults": false` to drop them),
2. `~/.pi/agent/permissions.json` (linked from `programs/pi/agent/permissions.json`),
3. `<project>/.pi/permissions.json`, only when the project is trusted,
4. per-agent rules: `agents.<name>.permissions` in those files, then
   `permission:`/`permissions:` in the agent's frontmatter
   (`~/.pi/agent/agents/<name>.md`, or `.pi/agents/<name>.md` in a trusted project).
   The main session uses the agent name `main`.

```json
{
  "permissions": [
    { "action": "shell", "resource": "*", "effect": "ask" },
    { "action": "shell", "resource": "git *", "effect": "allow" },
    { "action": "shell", "resource": "git push *", "effect": "ask" },
    { "action": "shell", "resource": "rm *", "effect": "deny" },
    { "action": "external_directory", "resource": "~/notes/*", "effect": "allow" },
    { "action": "subagent", "resource": "*", "effect": "deny" },
    { "action": "subagent", "resource": "Explore", "effect": "allow" }
  ],
  "agents": {
    "Explore": {
      "permissions": [{ "action": "edit", "resource": "*", "effect": "deny" }]
    }
  }
}
```

The v1 object shape is accepted too, in key order: `"permission": { "bash": { "*": "ask", "git *": "allow" }, "edit": "deny" }`.
In agent frontmatter:

```yaml
---
tools: read, bash, grep
permission:
  bash:
    "*": ask
    "ls *": allow
  edit: deny
---
```

### Patterns

`*` matches anything (including `/`), `?` one character, everything else is
literal and the whole value must match. A pattern ending in ` *` also matches
the bare command (`git status *` covers `git status`), and one ending in `/*`
also matches the directory itself. A leading `~` or `$HOME` is expanded for
`read`, `edit`, `list` and `external_directory`.

### Actions

| Action | Tool | Resource |
| --- | --- | --- |
| `shell` (alias `bash`) | `bash` | each command the scanner finds (see below) |
| `read` | `read` | path, project-relative inside the project, absolute outside |
| `edit` (aliases `write`, `patch`) | `edit`, `write` | path |
| `grep` | `grep` | the search pattern |
| `glob` (alias `find`) | `find` | the glob pattern |
| `list` (alias `ls`) | `ls` | path |
| `external_directory` | file tools, `cd` in `bash` | absolute directory outside the working directory |
| `subagent` (alias `task`) | `subagent` | the agent type |
| `skill` | reading a skill's files (`read`, or a path in `bash`), `/skill:name` | the skill name |
| `execute` (alias `codemode`) | `codemode` | `*`; tools a script calls are checked one by one |
| any other tool name | that tool (MCP tools, web tools, …) | `*` |

## How a call is decided

As in opencode: if any resource is denied by the configured rules, the call is
blocked, and approvals are never consulted for that, so they can never
override a deny. Otherwise approvals are appended and any resource that still
asks prompts. A tool whose action is denied for every resource is hidden from
the model.

The prompt offers *Allow once*, *Always allow this session* (the whole session
tree, subagents included), *Deny* and *Deny with feedback*. Approvals are kept
in memory only and never written to disk; put lasting rules in
`permissions.json`.
"Always" saves a prefix: `git status --short` saves `shell git status *`, using
an arity table like opencode's. `/permissions` lists the rules in effect;
`/permissions clear` forgets this session's approvals.

Without a UI (print or JSON mode, and no parent session), an ask is blocked.

## Shell commands

The scanner splits `&&`, `||`, `;`, pipes, `&`, newlines, subshells, `$(…)`,
backticks, `<(…)`, `if`/`for`/`while`/`case` bodies and function bodies, drops
`VAR=value` prefixes and redirections, removes quotes, and skips heredoc bodies.
Each command it finds must pass.

Unlike opencode it also looks through wrappers. The wrapper's own command line
and the command it runs are both checked, and the strictest answer wins, so a
`rm *` deny catches all of these:

- `sudo`, `doas`, `env`, `nohup`, `time`, `nice`, `ionice`, `timeout`,
  `stdbuf`, `setsid`, `flock`, `chrt`, `taskset`, `command`, `exec`, `builtin`
- `xargs …` (bare `xargs` runs `echo`), `find -exec/-execdir/-ok`, `fd -x/-X`
- `bash|sh|zsh|dash|… -c '…'`, `eval '…'`, `watch '…'`, `nix-shell --run '…'`,
  `nix develop|shell -c …` (the script is scanned recursively)

Commands the scanner cannot see into are **opaque**: a command name or
`-c` script built from variables (`$cmd …`, `bash -c "$X"`), inline code
(`python -c`, `node -e`, `perl -e`, `awk` programs calling `system`), `sudo -i`,
`env -S` and anything that fails to parse. A catch-all rule (resource `*`, or
no rule) does not allow an opaque command; it asks instead. A specific rule
such as `python3 *` still applies. Scripts (`./deploy.sh`, `make`,
`python x.py`) are judged by their command line only, as in opencode.

## Skills

A skill that `skill` rules deny is removed from the skills listed in the
system prompt, so the agent never sees it. Reading any file in its directory
is blocked, whether through `read` or a path in a `bash` command. Typing
`/skill:name` for it does nothing except show a warning. If a skill is set to
`ask`, it stays listed and the agent's first read of it prompts. A
`/skill:name` you type yourself counts as your approval.

```json
{ "action": "skill", "resource": "*", "effect": "deny" },
{ "action": "skill", "resource": "todoist", "effect": "allow" }
```

## Subagents

With `@gotgenes/pi-subagents`, which runs subagents in-process:

- The `subagent` action is checked against the target agent before a child is
  created, under the calling agent's rules.
- A child is judged by its own agent's rules (detected from the
  `<active_agent>` tag pi-subagents puts in its system prompt), not its
  parent's, like opencode. Tools the agent denies entirely are hidden from it.
- A child has no UI of its own, so its asks are shown in the parent session's
  UI, labelled `subagent <name>`. Prompts are queued one at a time. A child
  started with `PI_SUBAGENT_PARENT_SESSION` but in another process cannot
  reach the parent and its asks are blocked.

This relies on pi-subagents' `subagents:child:spawning`,
`subagents:child:session-created` and `subagents:child:disposed` events, and a
process-global registry (`Symbol.for("pi-permissions:registry")`) that each
session's copy of this extension shares.

Do not install `pi-permission-system` alongside this extension: both gate
the same calls.

## Tests

```sh
node --experimental-strip-types --test test/*.test.ts
```

`test/index.test.ts` exercises the extension with a fake pi and is skipped
unless `@earendil-works/pi-coding-agent` can be imported (for example with a
temporary `node_modules` symlink to an `npm i @earendil-works/pi-coding-agent`).
