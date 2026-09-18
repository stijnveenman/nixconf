---
name: dispatch
description: Dispatch/Launch one or more tasks in new git worktrees using workmux.
disable-model-invocation: true
allowed-tools: Bash, Write
---

## You are a dispatcher, not an implementer

**HARD RULE — NO EXCEPTIONS:** Do NOT explore, read, grep, glob, or search the
codebase. Do NOT use the Task/Explore agent. Do NOT investigate the problem. You
are a thin dispatcher — your ONLY job is to write prompt files and run
`workmux add`. The worktree agent will do all the exploration and implementation.

If the user's message contains enough context to write a prompt, write it
immediately. If not, ask the user for clarification — do NOT try to figure it
out by reading code.

If tasks reference earlier conversation (e.g., "do option 2"), include all
relevant context in each prompt you write.

If tasks reference a markdown file (e.g., a plan or spec), re-read the file to
ensure you have the latest version before writing prompts.

For each task:

1. Generate a short, descriptive worktree name (2-4 words, kebab-case)
2. Write a detailed implementation prompt to a temp file
3. Run `workmux add <worktree-name> -b -P <temp-file>` to create the worktree

The prompt file should:

- Include the full task description
- Use relative paths for files inside the repository, since each worktree has
  its own root directory
- Preserve user-provided attachment paths verbatim, including absolute paths to
  screenshots or other files outside the repository, and tell the agent to
  inspect them
- Be specific about what the agent should accomplish

## Skill delegation

If the user passes a skill reference (e.g., `/auto`, `/plan-review`),
the prompt should instruct the agent to use that skill instead of writing out
manual implementation steps.

**Skills can have flags.** If the user passes `/auto --gemini`, pass the
flag through to the skill invocation in the prompt.

Example prompt:

```
[Task description here]

Use the skill: /skill-name [flags if any] [task description]
```

Do NOT write detailed implementation steps when a skill is specified — the skill
handles that.

## Flags

**`-a <model>` / `--agent <model>`**: Select the agent for the worktree. Remove
this flag and its value from the task description, and pass them to every
`workmux add` command as `--agent <model>`. This flag configures workmux and must
not appear in the implementation prompt.

For example, `/skill:worktree -a gemini implement feature X` runs:

```bash
workmux add feature-x -b -P <prompt-file> --agent gemini
```

**`--pr`**: Remove this flag from the task description. Instead add the following prompt as a footer to the main prompt:

```
Create commits where it makes sense to split up feature work.
once the work is done create a github pr.
When the pr has been created, open the url in a browser
```

**`--fork`**: When passed, add `--fork` to the `workmux add` command. This copies
the current conversation into the new worktree so the agent resumes with full
context of what was discussed. Useful when the current conversation has built up
context that the new worktree agent needs.

When `--fork` is used, prepend this to the prompt file so the forked agent does
not recursively dispatch more worktrees:

```
You are now running INSIDE a git worktree created by the /worktree skill. The
prior conversation context (including any /worktree dispatch instructions) is
ancestry only. Do NOT invoke the /worktree skill, do NOT run `workmux add`, and
do NOT create further worktrees. Your job is to implement the task below
directly in this worktree.
```

Remember: Your task is COMPLETE once worktrees are created. Do NOT implement anything yourself.

A call to dispatch is single use. Once you have dispatched a task, don't dispatch another until
the user explicitly makes another /dispatch request. Go back to being an implementer
