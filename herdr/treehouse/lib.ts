import {$} from "bun"
import config from "./runtime.json"

export type Lease = {
  path: string
  status: string
  lease_id: string
  lease_holder: string
}

export async function run(args: string[], cwd?: string) {
  const result = cwd
    ? await $`cd ${cwd} && ${args}`.quiet().nothrow()
    : await $`${args}`.quiet().nothrow()

  return {
    ok: result.exitCode === 0,
    stdout: result.stdout.toString().trim(),
    stderr: result.stderr.toString().trim(),
  }
}

export async function json<T>(args: string[], cwd?: string): Promise<T> {
  const result = await run(args, cwd)
  if (!result.ok) throw new Error(result.stderr || `${args[0]} failed`)
  return JSON.parse(result.stdout) as T
}

export async function prompt(args: string[]) {
  const process = Bun.spawn(args, {stdin: "inherit", stdout: "pipe", stderr: "inherit"})
  const stdout = await new Response(process.stdout).text()
  const exitCode = await process.exited
  return {ok: exitCode === 0, stdout: stdout.trim()}
}

export async function treehouseLease(path: string): Promise<Lease | undefined> {
  const leases = await json<Lease[]>([config.treehouse, "status", "--json"], path)
  const target = await realpath(path)

  for (const lease of leases) {
    const leasePath = await realpath(lease.path)
    if (leasePath === target && lease.status === "leased" && lease.lease_holder === "herdr") {
      return lease
    }
  }
}

export async function returnLease(lease: Lease, force = false) {
  return run([
    config.treehouse,
    "return",
    ...(force ? ["--force"] : []),
    "--if-lease-id",
    lease.lease_id,
    "--if-lease-holder",
    "herdr",
    lease.path,
  ])
}

export async function holdError(message: string): Promise<never> {
  process.stderr.write(`\u001b[31m${message}\u001b[0m\n\nPress any key to close`)
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true)
    await new Promise<void>((resolve) => process.stdin.once("data", () => resolve()))
    process.stdin.setRawMode(false)
  }
  process.exit(1)
}

export function errorText(result: {stderr: string; stdout: string}) {
  return result.stderr || result.stdout || "Command failed"
}

async function realpath(path: string) {
  const result = await run([config.git, "-C", path, "rev-parse", "--show-toplevel"])
  return result.ok ? result.stdout : path
}

export {config}
