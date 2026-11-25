# Activate an already-built NixOS system closure. Runs as root via a
# NOPASSWD sudoers rule, so it accepts exactly one argument and does nothing
# but set the system profile and run `switch-to-configuration switch`.
set -euo pipefail
export PATH="$coreutils_bin"

die() {
  echo "nixos-switch: $*" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "usage: nixos-switch <nixos-system-store-path>"

path=$(realpath -e -- "$1") || die "no such path: $1"
[[ "$path" =~ ^/nix/store/[0-9a-z]{32}-nixos-system-[^/]+$ ]] ||
  die "not a NixOS system closure: $path"
"$nix_store" --check-validity "$path" 2>/dev/null || die "not a valid store path: $path"
[ -f "$path/nixos-version" ] && [ -x "$path/bin/switch-to-configuration" ] ||
  die "not a NixOS system closure: $path"

"$nix_env" --profile /nix/var/nix/profiles/system --set "$path"
exec "$path/bin/switch-to-configuration" switch
