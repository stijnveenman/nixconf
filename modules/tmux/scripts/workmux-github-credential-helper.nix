{pkgs}: let
  security = "/usr/bin/security";
  id = "/usr/bin/id";
in
  pkgs.writeShellScript "workmux-github-credential-helper" ''
    set -euo pipefail

    account="$(${id} -un)"

    case "''${1:-}" in
      get)
        while IFS= read -r line; do
          [ -n "$line" ] || break
        done
        printf '%s\n' 'username=x-access-token'
        printf 'password=%s\n' "$(${security} find-generic-password -a "$account" -s workmux-github-pat -w)"
        ;;
      store|erase)
        ;;
    esac
  ''
