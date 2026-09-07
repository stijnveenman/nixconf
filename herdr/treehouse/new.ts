import {config, errorText, holdError, json, prompt, returnLease, run, type Lease} from "./lib"

type PaneResponse = {result: {pane: {foreground_cwd?: string; cwd?: string}}}
type LeaseResponse = Lease & {base_branch?: string}
type WorkspaceResponse = {result: {workspace: {workspace_id: string}}}

try {
  const pane = await json<PaneResponse>([config.herdr, "pane", "current"])
  const cwd = pane.result.pane.foreground_cwd || pane.result.pane.cwd
  if (!cwd) throw new Error("Could not determine the focused pane's working directory.")

  const repo = await run([config.git, "-C", cwd, "rev-parse", "--show-toplevel"])
  if (!repo.ok) throw new Error(`Not inside a Git repository: ${cwd}`)
  const repoName = repo.stdout.split("/").at(-1)!

  const nameInput = await prompt([
    config.gum,
    "input",
    "--header",
    `New pooled workspace (${repoName})`,
    "--placeholder",
    "workspace name",
    "--prompt",
    "name > ",
  ])
  if (!nameInput.ok) process.exit(0)
  const name = nameInput.stdout.replace(/[\x00-\x1f\x7f]/g, "").trim()
  if (!name) throw new Error("A workspace name is required.")

  const baseInput = await prompt([
    config.gum,
    "input",
    "--header",
    "Base branch (blank = repo default)",
    "--placeholder",
    "leave blank for default",
    "--prompt",
    "base > ",
  ])
  if (!baseInput.ok) process.exit(0)
  const base = baseInput.stdout.replace(/[\x00-\x1f\x7f]/g, "").trim()

  process.stderr.write("Leasing a worktree from the pool...\n")
  const lease = await json<LeaseResponse>([
    config.treehouse,
    "get",
    "--lease",
    "--lease-holder",
    "herdr",
    "--no-fetch",
    "--json",
    ...(base ? ["--base", base] : []),
  ], cwd)

  try {
    let branch = name
      .toLowerCase()
      .replace(/[^a-z0-9._/-]+/g, "-")
      .replace(/-+/g, "-")
      .replace(/\/+/g, "/")
      .replace(/^[-._/]+|[-._/]+$/g, "") || "workspace"
    const stem = branch
    let suffix = 2

    while ((await run([config.git, "-C", lease.path, "show-ref", "--verify", "--quiet", `refs/heads/${branch}`])).ok) {
      branch = `${stem}-${suffix++}`
    }

    const checkout = await run([config.git, "-C", lease.path, "switch", "-c", branch])
    if (!checkout.ok) throw new Error(errorText(checkout))

    const created = await json<WorkspaceResponse>([
      config.herdr,
      "workspace",
      "create",
      "--cwd",
      lease.path,
      "--label",
      name,
      "--focus",
    ])
    const workspaceId = created.result.workspace.workspace_id

    await run([
      config.herdr,
      "workspace",
      "report-metadata",
      workspaceId,
      "--source",
      "treehouse",
      "--token",
      `repo=${repoName}`,
      "--token",
      `branch=${branch}`,
    ])
  } catch (error) {
    await returnLease(lease, true)
    throw error
  }
} catch (error) {
  await holdError(error instanceof Error ? error.message : String(error))
}
