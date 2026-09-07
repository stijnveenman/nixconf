import {$} from "bun"
import {resolve} from "node:path"

const [herdr] = process.argv.slice(2)
if (!herdr) throw new Error("Usage: herdr-treehouse-activate <herdr>")
const plugin = resolve(import.meta.dir, "../share/herdr/plugins/treehouse")

process.env.HERDR_SOCKET_PATH = `${process.env.TMPDIR || "/tmp"}/treehouse-plugin-activation.sock`

await $`${herdr} plugin uninstall threehouse.pool`.quiet().nothrow()
await $`${herdr} plugin uninstall treehouse.pool`.quiet().nothrow()

const linked = await $`${herdr} plugin link ${plugin}`.quiet().nothrow()
if (linked.exitCode !== 0) throw new Error(linked.stderr.toString().trim() || "Could not link treehouse.pool")
