{
  lib,
  pkgs,
  workmux,
  workmuxGithubAskpass,
}: let
  find = lib.getExe' pkgs.findutils "find";
  jq = lib.getExe pkgs.jq;
  tmux = lib.getExe pkgs.tmux;
  tmuxBinDir = builtins.dirOf tmux;
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
in
  pkgs.writeShellScript "workmux-gone-cleanup" ''
    set -uo pipefail

    # launchd does not provide the Home Manager package PATH. Workmux invokes
    # tmux by name, so make the exact tmux used below discoverable to it.
    export PATH="${tmuxBinDir}:$PATH"

    export GIT_CONFIG_COUNT=3
    export GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf'
    export GIT_CONFIG_VALUE_0='git@github.com:'
    export GIT_CONFIG_KEY_1='url.https://github.com/.insteadOf'
    export GIT_CONFIG_VALUE_1='ssh://git@github.com/'
    export GIT_CONFIG_KEY_2='credential.helper'
    export GIT_CONFIG_VALUE_2=
    export GIT_ASKPASS="${workmuxGithubAskpass}"
    export GIT_TERMINAL_PROMPT=0

    patNotified=0
    printf '%s: cleaning worktrees with deleted upstream branches\n' "$(${pkgs.coreutils}/bin/date '+%Y-%m-%dT%H:%M:%S%z')"
    while IFS= read -r socket; do
      [ -S "$socket" ] || continue
      ${tmux} -S "$socket" list-sessions >/dev/null 2>&1 || continue
      socket="$(cd "$(dirname "$socket")" && pwd -P)/$(basename "$socket")"
      tmuxServerPid="$(${tmux} -S "$socket" display-message -p '#{pid}')"
      tmuxPane="$(${tmux} -S "$socket" list-panes -a -F '#{pane_id}' | ${pkgs.coreutils}/bin/head -n 1)"
      [ -n "$tmuxPane" ] || continue
      export TMUX="$socket,$tmuxServerPid,0"
      export TMUX_PANE="$tmuxPane"
      while IFS= read -r repo; do
        [ -d "$repo" ] || continue
        output="$(cd "$repo" && ${workmuxExe} remove --gone --force 2>&1)" || {
          printf '%s\n' "$output" >&2
          case "$output" in
            *401*|*403*|*Authentication*|*authentication*|*"terminal prompts disabled"*)
              if [ "$patNotified" -eq 0 ] && [ -x /usr/bin/osascript ]; then
                /usr/bin/osascript -e 'display notification "The GitHub PAT used by Workmux cleanup may be expired or invalid." with title "Workmux cleanup authentication failed"'
                patNotified=1
              fi
              ;;
          esac
          continue
        }
        printf '%s\n' "$output"
      done < <(${workmuxExe} list --all --json | ${jq} -r '.[].project_path' | ${pkgs.coreutils}/bin/sort -u)
    done < <(${find} "/tmp/tmux-$UID" -maxdepth 1 -type s -print)
  ''
