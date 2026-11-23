---
name: pr-review
description: Review a GitHub pull request into a tuicr review session, check it against its Jira ticket, and report summary, merge risk and a recommendation.
disable-model-invocation: true
---

Review a pull request. Arguments: `<owner/repo>#<number> tuicr session: <slug>`.
If the session is missing, use the `gh:<owner/repo>/pr/<number>` entry from
`tuicr review list --repo <owner/repo>`; tuicr must have the PR open for it to exist.

## Ground rules

- The working tree is the user's main checkout: read it, never change it. No
  checkout, switch, reset, stash, commit or edits.
- Never write to GitHub (no comments, reviews, approvals or merges). Review
  comments go only into the tuicr session; the user submits them from tuicr.

## Gather

1. `gh pr view <n> -R <repo> --json title,body,author,baseRefName,headRefName,headRefOid,commits,files,url`
2. `gh pr diff <n> -R <repo>`: review every changed file, not a sample.
3. For full files at the PR head, fetch without checking out:
   `git fetch <remote> refs/pull/<n>/head`, using the remote that points at
   `<repo>`, then `git show FETCH_HEAD:<path>`. Read surrounding and calling
   code wherever a change's correctness depends on it.
4. Jira: look for ticket keys (`ABC-123`) or Atlassian links in the title,
   body, branch name and commit messages. For each, read it with
   `acli jira workitem view <KEY>` and compare the change against its
   description and acceptance criteria: unmet requirements, partial coverage
   and unrelated scope. If `acli` is missing or fails, say so in the report.

## What to comment on

Only findings worth the author's time, focused on:

- Correctness: bugs, wrong edge cases, error handling, races, security,
  data loss, broken contracts or migrations, behavior that misses the ticket.
- Maintainability: designs that will be hard to change or understand, risky
  logic without tests.

No nitpicks: no style, formatting, naming taste, typos in code, optional
refactors or praise. If unsure whether something is a real problem, ask a
`question` instead of asserting an `issue`.

## Write comments to tuicr

First read existing comments (`tuicr review comments --session <slug>`); do not
duplicate them, and never touch comments whose author is not `pi-review`.

Add each comment with JSON input:

```bash
tuicr review add --session <slug> --input - <<'JSON'
{"type": "issue", "author": "pi-review", "file": "src/x.rs", "line": 42, "side": "new",
 "content": "`parse` returns early on an empty list, so `total` stays stale."}
JSON
```

- `type` is `issue` or `question`.
- Anchor to lines inside the diff hunks: `side: "new"` with the line number in
  the PR head file (check it against `git show FETCH_HEAD:<path> | nl -ba`), or
  `side: "old"` for removed lines. Use `start_line`/`end_line` for a range and
  only `file` when no line fits.
- One finding per comment, one to three sentences: the problem, why it matters,
  and the fix when it is not obvious.
- A review-level comment (no `file`) only for something important that has no
  line, such as an unmet ticket requirement. Never a summary or approval.

## Report in the chat

Keep it short; the details live in tuicr:

- **Summary**: what the PR changes, in two or three sentences.
- **Jira**: per ticket, whether the requirements are met (only when a ticket is linked).
- **Risk**: low, medium or high, with one sentence on why.
- **Recommendation**: approve, approve after the comments, or request changes, with one sentence.
- **Comments**: one line per tuicr comment (`path:line`: gist), or "none".

## Follow-ups

For the rest of this session, when a follow-up question, an answer from the
user or new information changes a finding, update the tuicr session to match:
add new comments, replace outdated ones (`tuicr review delete --session <slug>
--comment-id <id>` then add), and delete ones that no longer hold. Restate the
risk or recommendation only when it changes.
