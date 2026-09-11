{
  pkgs,
  lib,
}: let
  herdrBin = lib.getExe pkgs.herdr;
  gumBin = lib.getExe pkgs.gum;
  gitBin = lib.getExe pkgs.git;
in
  pkgs.writeShellScript "herdr-switch-nixconf" ''
    set -euo pipefail

    printf '\033]0;nixconf switch\007'

    flake_dir=''${NH_HOME_FLAKE:-/Users/sv/Documents/nixconf}

    if [ ! -d "$flake_dir" ]; then
      ${gumBin} style --foreground red "nixconf directory not found: $flake_dir"
      exit 1
    fi

    ${gumBin} style --foreground cyan "Switching nixconf from $flake_dir"
    cd "$flake_dir" || exit 1

    if [ -n "$(${gitBin} status --porcelain)" ]; then
      ${gumBin} style --foreground yellow "Working tree is dirty; skipping fetch from origin main."
    else
      ${gumBin} style --foreground cyan "Fetching latest nixconf from origin main..."
      if ! ${gitBin} pull --ff-only origin main; then
        ${gumBin} style --foreground red "Fetch failed (diverged or no upstream?). Fix it and retry."
        read -s -n1 -p "Press any key to close..."
        exit 1
      fi
    fi

    ${gumBin} style --foreground cyan "Switching nixconf home configuration..."
    if ! nh home switch "$flake_dir"; then
      ${gumBin} style --foreground red "nh home switch failed, see errors above."
      read -s -n1 -p "Press any key to close..."
      exit 1
    fi

    ${herdrBin} server reload-config >/dev/null 2>&1 || true

    ${gumBin} style --foreground green "nixconf switched successfully."
    read -s -n1 -p "Press any key to close..."
  ''
