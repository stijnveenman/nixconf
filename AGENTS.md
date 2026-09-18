# nixconf

This repo is a Nix [home-manager](https://github.com/nix-community/home-manager)
flake managed with [`nh`](https://github.com/nix-community/nh) (nix-helper).
Use `nh home` for Home Manager hosts and `nh os` for the NixOS host.

- Host `sv` (macOS, `aarch64-darwin`) lives at `~/Documents/nixconf`.
- Host `stiixxy` (Linux) lives at `~/nixconf`.

## Build and switch workflow (important)

When you change any `.nix` file, follow this order. **Never skip the build, and
never switch to a configuration that has not built successfully.**

1. **Format:** run `alejandra .` to format the Nix files in the repo.
2. **Build/validate:** run `nh <home/os> build .`. This evaluates and builds
   the current worktree without activating it. A non-zero exit code, Nix
   evaluation error, or build failure means validation **failed**. If the build
   succeeds, trust it; do not inspect generated `/nix/store` output.
3. **Switch:** after a successful build, switching is allowed in the main
   worktree. In another worktree, switch only when the user requests it. Use
   `nh <home/os> switch .`; do not add force flags or use lower-level activation
   commands.

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

## Reload notes (`nh` and `tmux`)

- `nh` does not have a separate daemon reload step; use the normal build and
  switch workflow.
- After a successful switch, reload tmux with
  `tmux source-file ~/.config/tmux/tmux.conf` (or restart tmux).

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
