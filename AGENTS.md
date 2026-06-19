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
3. **Apply (switch):** **the agent must only run `nh home switch` while it is
   executing the `/apply` slash command.** In every other context the agent must
   never run `nh home switch`. So when the user asks you to apply, activate, or
   switch outside of `/apply`, do **not** run `nh home switch` — instead, stop
   after a successful build, tell the user the config is built and ready, and
   remind them to run `/apply` when they choose.

   When you _are_ running `/apply`, you may run `nh home switch`, but only after
   `nh home build` has succeeded (see the gating below).

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
- `/apply` runs the build step and then switches only if the build passed. This
  is the **only** path through which the agent may run `nh home switch`.
  Each `/apply` grants a single switch attempt only.

## Formatting

`.nix` files in this repo are formatted with
[`alejandra`](https://github.com/kamadorueda/alejandra) (available on `PATH`).
When you edit a `.nix` file, you may run `alejandra <file>` (or `alejandra .`)
before building to keep formatting consistent.
