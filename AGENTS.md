# nixconf

This repo is a Nix [home-manager](https://github.com/nix-community/home-manager)
flake. It is managed with [`nh`](https://github.com/nix-community/nh)
(nix-helper), and `programs.nh.homeFlake` is set in each host, so `nh` resolves
the flake path and the correct host configuration automatically from the current
user. You do **not** need to pass a flake path or a host name.

- Host `sv` (macOS, `aarch64-darwin`) lives at `~/Documents/nixconf`.
- Host `stiixxy` (Linux) lives at `~/nixconf`.
- The same `nh home` commands below work on both hosts.

## Validate / apply workflow (important)

When you change any `.nix` file, follow this order. **Never skip the build, and
never switch on a config that has not built successfully.**

1. **Format:** run `alejandra .` to format the Nix files in the repo.
2. **Validate (build):** run `nh home build`. This evaluates and builds the
   home-manager configuration without activating it. A non-zero exit code, a Nix
   evaluation error, or a build failure means validation **failed**.
3. **Apply (switch):** **the agent must never run `nh home switch`.** Applying
   the configuration is a manual step the user performs themselves by running
   the `/apply` slash command. After a successful build, stop and tell the user
   the config is built and ready, then let them run `/apply` when they choose.
   Do not run `nh home switch` even if the user asks you to apply, activate, or
   switch — instead, remind them to run `/apply` manually.

If the build fails:

- Stop. Do **not** run `nh home switch`.
- Report the Nix evaluation/build error to the user and fix the offending `.nix`
  before retrying the build.

There are slash commands for these steps:

- `/validate` runs the build step.
- `/apply` runs the build step and then switches only if the build passed. This
  is **user-invoked only**; the agent does not run it.

## Formatting

`.nix` files in this repo are formatted with
[`alejandra`](https://github.com/kamadorueda/alejandra) (available on `PATH`).
When you edit a `.nix` file, you may run `alejandra <file>` (or `alejandra .`)
before building to keep formatting consistent.
