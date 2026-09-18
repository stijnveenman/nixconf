---
name: commit
description: commit unchanged work, and optionally push upstream
allowed-tools: Read, Bash, Glob, Grep
---

This command finished work on the current branch.

1. Commit all uncommitted changes.
2. Push to the upstream if allowed

## Flags

Strip all flags from the arguments to other commands

**`-p` / `--push`**: allow setting the upstream if not already set for the current push.

## Step 1. Commit

Check for staged, unstaged, and untracked changes with `git status --porcelain`.
Create a commit per logical unit of work or seperate feature.
Use lowercase, imperative mood, succint commit messages.
Skip if the working tree is clean.

## Step 2. Push

Check if the current branch has an upstream with `git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'`
If the branch already has an upstream, push to the upstream
If the branch does not have an upstream, only push if the push flag was set
