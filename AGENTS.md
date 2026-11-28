# nixconf

This repo is a Nix [home-manager](https://github.com/nix-community/home-manager)
flake managed with [`nh`](https://github.com/nix-community/nh) (nix-helper).
Use `nhb` (build) and `nhs` (switch) on every host. They are installed by `modules/core/nh.nix` and run the right `nh os|home|darwin` subcommand for the host (set via `my.nh.subcommand`).

## Layout (flake-parts, dendritic)

- `flake.nix` only declares inputs; every `.nix` file under `modules/` is a
  flake-parts module loaded by import-tree (paths with a `_`-prefixed segment
  are skipped). Keep non-module Nix helpers out of `modules/` or under `_`.
- Feature files publish modules as `flake.modules.<nixos|homeManager>.<name>`
  and close over flake `inputs` instead of using `specialArgs`.
- `modules/hosts/<host>/default.nix` builds the configuration and lists the
  module order; `<host>/home.nix` etc. hold the host's own modules.
- The registry is `modules/flake/modules.nix`, not flake-parts'
  `flakeModules.modules`: it avoids extra import nesting, because import depth
  and order decide how list options (e.g. `home.packages`) merge and so change
  store paths. When restructuring, compare `drvPath`s before and after.

- Host `sv` (macOS, `aarch64-darwin`) lives at `~/Documents/nixconf`.
- Host `nnn` (NixOS, user `stiixxy`) lives at `~/nixconf`.

## Build and switch workflow (important)

When you change any `.nix` file, follow this order. **Never skip the build, and
never switch to a configuration that has not built successfully.**

1. **Format:** run `alejandra .` to format the Nix files in the repo.
2. **Build/validate:** run `nhb .`. This evaluates and builds
   the current worktree without activating it. A non-zero exit code, Nix
   evaluation error, or build failure means validation **failed**. If the build
   succeeds, trust it; do not inspect generated `/nix/store` output.
3. **Switch:** after a successful build, switch in the main worktree by
   default, without waiting to be asked. In another worktree, switch only when
   the user requests it. Use `nhs .`; do not add force flags or use lower-level
   activation commands.

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

## herdr-remote

Follow the normal build and switch rules when working on the VM itself. Ask
permission before using NixOS Anywhere or running a remote build or switch for
this VM. Only mention updating it when the user explicitly asks for changes to
this machine. See `modules/hosts/herdr-remote/README.md` for update and install commands;
NixOS Anywhere's default install flow erases the configured disk.

## Claude cloud sessions

GitHub tarball and API downloads are blocked there (git fetches work), so
`github:` inputs fail to fetch. The environment's setup script runs
`scripts/prefetch-github-inputs.sh`; rerun it after `flake.lock` changes. `nh`
refuses to run as root, so build with `nix build --no-link
.#nixosConfigurations.nnn.config.system.build.toplevel` (never switch a real
host); derivations that download from blocked hosts still fail.

The setup script also activates host `claude` (`modules/hosts/claude`, user
`root`) from `main` via `scripts/activate-claude-host.sh`; keep it minimal, as it
is built on every fresh container.

## Reload notes

`nh` does not have a separate daemon reload step; use the normal build and
switch workflow. Reload a running Herdr server after changing its config with
`herdr server reload-config`.

## Searching packages

Always use `nh search <query>` to find packages; do not use `nix search`.

## Formatting

`.nix` files in this repo are formatted with
[`alejandra`](https://github.com/kamadorueda/alejandra) (available on `PATH`).
When you edit a `.nix` file, you may run `alejandra <file>` (or `alejandra .`)
before building to keep formatting consistent.

## Upstream code changes

Never add package patches to implement behavior that requires upstream code
changes. Explain the limitation and leave upstream behavior unchanged.

## Comments

Do not add code comments unless they explain a specific edge case or
non-obvious behaviour.

## Script conventions

- Keep scripts close to the module that uses them: `<module>/scripts/*.sh`.
- If a module is currently a single file (`<name>.nix`) and needs scripts,
  convert it to a directory module with `<name>/default.nix`.
- Implement scripts with `pkgs.writeShellScript` in the module's `let` block,
  reading the `.sh` with `builtins.readFile`.
- Prefer inheriting full arguments in modules (`{ pkgs, lib, ... }`) instead of
  threading ad-hoc variables.
- Resolve binaries in a `let` block with `lib.getExe`, keeping variable names
  close to package names (for example: `git = lib.getExe pkgs.git;`).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
