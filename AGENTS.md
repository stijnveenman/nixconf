# nixconf

This repo is a Nix [home-manager](https://github.com/nix-community/home-manager)
flake. It is managed with [`nh`](https://github.com/nix-community/nh)
(nix-helper), and `programs.nh.homeFlake` is set in each host, so `nh` resolves
the flake path and the correct host configuration automatically from the current
user. You do **not** need to pass a flake path or a host name.

- Host `sv` (macOS, `aarch64-darwin`) lives at `~/Documents/nixconf`.
- Host `stiixxy` (Linux) lives at `~/nixconf`.
- Use `nh home` for the Home Manager hosts and `nh os` for the NixOS host.

## NixOS MCP (verify before you edit)

This project has the [`mcp-nixos`](https://github.com/utensils/mcp-nixos) server
configured (see `opencode.json`) under the name `nixos`. **Whenever you make any
change to a `.nix` file, use this MCP to verify package and option names instead
of relying on memory.** Confidently hallucinated package names, attribute paths,
and option names are exactly the failure mode this MCP exists to prevent.

Before adding or editing a `.nix` file, use the `nixos` MCP to confirm:

- **Packages** exist before referencing them (e.g. in `home.packages` or
  `environment.systemPackages`) — check the correct attribute path.
- **Option names** are spelled and namespaced correctly, against the right
  source for what you are editing:
  - `home-manager` for home-manager options (this repo is primarily
    home-manager).
  - `darwin` for nix-darwin options (host `sv`, `aarch64-darwin`).
  - `nixos` for NixOS packages/options.
  - `nixvim` for Neovim configuration options, where relevant.
- **Function signatures** (via the `noogle` source) when using less common
  `lib` helpers.

Verifying with the MCP does **not** replace the build — it reduces the chance
the build fails on a bad name. Always still follow the validate/apply workflow
below.

## Validate / apply workflow (important)

When you change any `.nix` file, follow this order. **Never skip the build, and
never switch on a config that has not built successfully.**

1. **Format:** run `alejandra .` to format the Nix files in the repo.
2. **Validate (build):** run `nh home build` for a Home Manager configuration or
   `nh os build` for a NixOS configuration. This evaluates and builds without
   activating. A non-zero exit code, Nix evaluation error, or build failure
   means validation **failed**. If the build **succeeds**, trust it: treat the
   result as correct and do **not** inspect, read, or dive into `/nix/store`
   output to double-check the generated files.

   In a disposable firstmate worktree, plain `nh home build` resolves `nh` to
   the primary checkout via the `NH_HOME_FLAKE` env var / `programs.nh.homeFlake`
   (e.g. `~/Documents/nixconf`), silently building the **wrong** tree. When
   validating worktree changes, pass the worktree path explicitly:
   `nh home build <absolute-worktree-path>`. `NH_HOME_FLAKE` is set by the host
   environment, so this applies even though `nh` is run from inside the worktree.
3. **Apply (switch):** after a successful build, activate the configuration by
   running `nh home switch` for Home Manager or `nh os switch` for NixOS, unless
   the user requested validation only. These are the only permitted switch
   commands. Do not add force flags or use lower-level activation commands.

   The `/apply` command assumes the configuration has already built successfully
   and runs only the appropriate switch command. It does not format or build.

If the build fails:

- Stop. Do **not** run a switch command.
- Report the Nix evaluation/build error to the user and fix the offending `.nix`
  before retrying the build.

If the switch (activation) fails:

- Stop immediately and report the activation error.
- Do **not** retry the switch.
- Do **not** run other commands, modify or remove files, or add force flags to
  resolve the failure, including conflicts with existing configuration files.
- Leave remediation to the user unless they later make a separate request.

There are slash commands for these steps:

- `/validate` formats and runs the appropriate build command without switching.
- `/apply` runs only the appropriate `nh home switch` or `nh os switch` command.
  It assumes the build has already succeeded.

## Formatting

`.nix` files in this repo are formatted with
[`alejandra`](https://github.com/kamadorueda/alejandra) (available on `PATH`).
When you edit a `.nix` file, you may run `alejandra <file>` (or `alejandra .`)
before building to keep formatting consistent.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
