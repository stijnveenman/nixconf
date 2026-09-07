import {config, errorText, json, returnLease, run, treehouseLease} from "./lib"

type CloseEvent = {
  data?: {
    workspace?: {
      label?: string
      worktree?: {checkout_path?: string}
    }
  }
}
type WorkspaceResponse = {result: {workspace: {workspace_id: string}}}

try {
  const event = JSON.parse(process.env.HERDR_PLUGIN_EVENT_JSON || "{}") as CloseEvent
  const path = event.data?.workspace?.worktree?.checkout_path
  if (!path) process.exit(0)

  const lease = await treehouseLease(path)
  if (!lease) process.exit(0)

  const returned = await returnLease(lease)
  if (returned.ok) process.exit(0)

  const reopened = await json<WorkspaceResponse>([
    config.herdr,
    "workspace",
    "create",
    "--cwd",
    path,
    "--label",
    event.data?.workspace?.label || "Treehouse workspace",
    "--focus",
  ])
  const workspaceId = reopened.result.workspace.workspace_id
  const popup = await run([
    config.herdr,
    "plugin",
    "pane",
    "open",
    "--plugin",
    "treehouse.pool",
    "--entrypoint",
    "confirm-force",
    "--workspace",
    workspaceId,
    "--env",
    `TREEHOUSE_PATH=${path}`,
    "--env",
    `TREEHOUSE_WORKSPACE_ID=${workspaceId}`,
    "--env",
    `TREEHOUSE_ERROR=${errorText(returned)}`,
  ])
  if (!popup.ok) throw new Error(`${errorText(returned)}\n\nCould not open confirmation popup: ${errorText(popup)}`)
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`)
  process.exit(1)
}
