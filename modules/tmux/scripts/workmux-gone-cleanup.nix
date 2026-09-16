{
  lib,
  pkgs,
  workmux,
}: let
  jq = lib.getExe pkgs.jq;
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
in
  pkgs.writeShellScript "workmux-gone-cleanup" ''
    set -uo pipefail

    runtimeDir="''${TMPDIR:-/tmp}"
    lockDir="$runtimeDir/workmux-gone-cleanup-$UID.lock"
    stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/workmux"
    logFile="$stateDir/gone-cleanup.log"

    ${pkgs.coreutils}/bin/mkdir -p "$stateDir"

    if ! ${pkgs.coreutils}/bin/mkdir "$lockDir" 2>/dev/null; then
      if [ -r "$lockDir/pid" ] && kill -0 "$(<"$lockDir/pid")" 2>/dev/null; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/rm -rf "$lockDir"
      ${pkgs.coreutils}/bin/mkdir "$lockDir" || exit 0
    fi
    trap '${pkgs.coreutils}/bin/rm -rf "$lockDir"' EXIT HUP INT TERM
    printf '%s\n' "$$" >"$lockDir/pid"

    while :; do
      {
        printf '%s: cleaning worktrees with deleted upstream branches\n' "$(${pkgs.coreutils}/bin/date '+%Y-%m-%dT%H:%M:%S%z')"
        while IFS= read -r repo; do
          [ -d "$repo" ] || continue
          (
            cd "$repo"
            ${workmuxExe} remove --gone --force
          )
        done < <(${workmuxExe} list --all --json | ${jq} -r '.[].project_path' | ${pkgs.coreutils}/bin/sort -u)
      } >>"$logFile" 2>&1

      ${pkgs.coreutils}/bin/sleep 300
    done
  ''
