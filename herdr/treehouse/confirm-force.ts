import {config, errorText, holdError, prompt, returnLease, run, treehouseLease} from "./lib"

try {
  const path = process.env.TREEHOUSE_PATH
  const workspaceId = process.env.TREEHOUSE_WORKSPACE_ID
  const returnError = process.env.TREEHOUSE_ERROR
  if (!path || !workspaceId || !returnError) throw new Error("Missing Treehouse return context.")

  const lease = await treehouseLease(path)
  if (!lease) process.exit(0)

  process.stderr.write(`${returnError}\n\n`)
  const confirmed = await prompt([
    config.gum,
    "confirm",
    "Force return this worktree? Uncommitted changes may be discarded.",
    "--affirmative",
    "Force return",
    "--negative",
    "Keep workspace",
  ])
  if (!confirmed.ok) process.exit(0)

  const forced = await returnLease(lease, true)
  if (!forced.ok) throw new Error(errorText(forced))

  await run([config.herdr, "workspace", "close", workspaceId])
} catch (error) {
  await holdError(error instanceof Error ? error.message : String(error))
}
