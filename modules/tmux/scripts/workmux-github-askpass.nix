{
  pkgs,
  lib,
}: let
  security = "/usr/bin/security";
in
  pkgs.writeShellScript "workmux-github-askpass" ''
    set -euo pipefail

    account="$(/usr/bin/id -un)"

    case "''${1:-}" in
      *Username*)
        printf '%s\n' 'x-access-token'
        ;;
      *Password*)
        ${security} find-generic-password \
          -a "$account" \
          -s workmux-github-pat \
          -w
        ;;
    esac
  ''
