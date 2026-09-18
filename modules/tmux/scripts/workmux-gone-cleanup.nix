{
  lib,
  pkgs,
  workmux,
}: let
  find = lib.getExe' pkgs.findutils "find";
  jq = lib.getExe pkgs.jq;
  tmux = lib.getExe pkgs.tmux;
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
in
  pkgs.writeShellScript "workmux-gone-cleanup" ''
    set -uo pipefail

    printf '%s: cleaning worktrees with deleted upstream branches\n' "$(${pkgs.coreutils}/bin/date '+%Y-%m-%dT%H:%M:%S%z')"
    while IFS= read -r socket; do
      [ -S "$socket" ] || continue
      ${tmux} -S "$socket" list-sessions >/dev/null 2>&1 || continue
      export TMUX="$socket,0,0"
      while IFS= read -r repo; do
        [ -d "$repo" ] || continue
        (
          cd "$repo"
          ${workmuxExe} remove --gone --force
        )
      done < <(${workmuxExe} list --all --json | ${jq} -r '.[].project_path' | ${pkgs.coreutils}/bin/sort -u)
    done < <(${find} "/tmp/tmux-$UID" -maxdepth 1 -type s -print)
  ''
