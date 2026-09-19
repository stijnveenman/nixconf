# Your job is to provide recommendations for the current task.

## Branch

Generate a concise git branch name based on the task description.

Rules:

- Use kebab-case (lowercase with hyphens)
- Keep it short: 1-3 words, max 4 if necessary
- Focus on the core task/feature, not implementation details
- No prefixes like feat/, fix/, chore/

Examples of good branch names:

- "Add dark mode toggle": dark-mode
- "Fix the search results not showing": fix-search
- "Refactor the authentication module": auth-refactor
- "Add CSV export to reports": export-csv
- "Shell completion is broken": shell-completion

## Agent

Determine what agent would be recommended for a given task. The following agents are available followed by when they should be used

Recommendations:

@agents

## Task

The user wants to create a a task to do the following in a new session
<task>
@task
</task>

Output MUST match exactly and ONLY the following lines. Do NOT output anything else

```
branch:<branch>
agent:<agent>
```
