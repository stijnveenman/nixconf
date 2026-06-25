# nixconf

This repo is a Nix [home-manager](https://github.com/nix-community/home-manager)
flake. It is managed with [`nh`](https://github.com/nix-community/nh)
(nix-helper), and `programs.nh.homeFlake` is set in each host, so `nh` resolves
the flake path and the correct host configuration automatically from the current
user. You do **not** need to pass a flake path or a host name.

- Host `sv` (macOS, `aarch64-darwin`) lives at `~/Documents/nixconf`.
- Host `stiixxy` (Linux) lives at `~/nixconf`.
- The same `nh home` commands below work on both hosts.

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
2. **Validate (build):** run `nh home build`. This evaluates and builds the
   home-manager configuration without activating it. A non-zero exit code, a Nix
   evaluation error, or a build failure means validation **failed**. If the build
   **succeeds**, trust it: treat the result as correct and do **not** inspect,
   read, or dive into `/nix/store` output to double-check the generated files —
   assume those outputs are correct.
3. **Apply (switch):** **the agent must only run `nh home switch` while it is
   executing the `/apply` slash command.** In every other context the agent must
   never run `nh home switch`. So when the user asks you to apply, activate, or
   switch outside of `/apply`, do **not** run `nh home switch` — instead, stop
   after a successful build, tell the user the config is built and ready, and
   remind them to run `/apply` when they choose.

   `/apply` itself does **not** format or build. It only runs `nh home switch`.
   The build is the precondition for switching, and it is expected to have been
   run successfully (for example via `/validate`) **before** the user runs
   `/apply`. So within `/apply` you do not run `alejandra .` or `nh home build`
   again — you go straight to `nh home switch`.

   **One-shot rule:** each `/apply` invocation authorises exactly one switch
   attempt. If `nh home switch` fails (activation error, rollback, or any
   non-zero exit), the authorisation is consumed and exhausted — even if the user
   subsequently asks you to "fix it and apply again" or uses equivalent wording.
   After any activation failure, you must stop, report the error, make any
   requested fixes, and then wait for the user to issue a new explicit `/apply`
   before running `nh home switch` again. Never re-run `nh home switch`
   automatically after a failure.

If the build fails:

- Stop. Do **not** run `nh home switch`, even during `/apply`.
- Report the Nix evaluation/build error to the user and fix the offending `.nix`
  before retrying the build.

If the switch (activation) fails:

- Stop immediately. Do **not** retry `nh home switch`.
- Report the activation error to the user.
- Make any requested fixes, then wait for a new explicit `/apply`.
- Never automatically re-run `nh home switch` after an activation failure,
  regardless of how the user phrases the follow-up request.

There are slash commands for these steps:

- `/validate` runs the build step.
- `/apply` runs only `nh home switch`. It does **not** format or build first —
  it assumes the build has already succeeded (e.g. via `/validate`). This is the
  **only** path through which the agent may run `nh home switch`. Each `/apply`
  grants a single switch attempt only.

## Formatting

`.nix` files in this repo are formatted with
[`alejandra`](https://github.com/kamadorueda/alejandra) (available on `PATH`).
When you edit a `.nix` file, you may run `alejandra <file>` (or `alejandra .`)
before building to keep formatting consistent.
