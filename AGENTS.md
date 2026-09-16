# nixconf

This repo is a Nix [home-manager](https://github.com/nix-community/home-manager)
flake. It is managed with [`nh`](https://github.com/nix-community/nh)
(nix-helper), and `programs.nh.homeFlake` is set in each host, so `nh` resolves
the flake path and the correct host configuration automatically from the current
user. You do **not** need to pass a flake path or a host name.

- Host `sv` (macOS, `aarch64-darwin`) lives at `~/Documents/nixconf`.
- Host `stiixxy` (Linux) lives at `~/nixconf`.
- Use `nh home` for the Home Manager hosts and `nh os` for the NixOS host.

## Validate / apply workflow (important)

When you change any `.nix` file, follow this order. **Never skip the build, and
never switch to a config that has not built successfully.**

1. **Format:** run `alejandra .` to format the Nix files in the repo.
2. **Validate (build):** run `nh home build`. This evaluates and builds without
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
3. **Switch:** after a successful build, activate the configuration with
   `nh home switch`, unless the user requested validation only. This is the only
   permitted switch command. Do not add force flags or use lower-level activation
   commands.

   The `/apply` command assumes the configuration has already built successfully
   and runs only `nh home switch`. It does not format or build.

If the build fails:

- Stop. Do **not** run a switch command.
- Report the Nix evaluation/build error to the user and fix the offending `.nix`
  before retrying the build.

If switch (activation) fails:

- Stop immediately and report the activation error to the user.
- Do **not** retry switch.
- Do **not** run other commands, modify or remove files, or add force flags to
  resolve the failure, including conflicts with existing configuration files.
- Leave remediation to the user unless they later make a separate request.

There are slash commands for these steps:

- `/validate` formats and runs `nh home build` without switching.
- `/apply` runs only `nh home switch`. It assumes the build has already
  succeeded.

## Reload notes (`nh` and `tmux`)

- `nh` does not have a separate daemon reload step. After changing `.nix`
  configuration, reload by following the normal flow: `nh home build` then
  `nh home switch`.
- Reload `tmux` only when tmux config/scripts change and after a successful
  switch. Use `tmux source-file ~/.config/tmux/tmux.conf` (or restart tmux).

## Formatting

`.nix` files in this repo are formatted with
[`alejandra`](https://github.com/kamadorueda/alejandra) (available on `PATH`).
When you edit a `.nix` file, you may run `alejandra <file>` (or `alejandra .`)
before building to keep formatting consistent.

## Script conventions

- Keep scripts close to the module that uses them: `modules/<module>/scripts`.
- If a module is currently a single file (`modules/<name>.nix`) and needs scripts,
  convert it to a directory module with `modules/<name>/default.nix`.
- Implement scripts with `pkgs.writeShellScript`.
- Prefer inheriting full arguments in modules (`{ pkgs, lib, ... }`) instead of
  threading ad-hoc variables.
- Resolve binaries in a `let` block with `lib.getExe`, keeping variable names
  close to package names (for example: `git = lib.getExe pkgs.git;`).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
