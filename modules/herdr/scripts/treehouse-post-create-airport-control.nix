{
  pkgs,
  lib,
  config,
}: let
  gitBin = lib.getExe pkgs.git;
  direnvBin = lib.getExe config.programs.direnv.package;
in
  pkgs.writeShellScript "treehouse-post-create-airport-control" ''
    set -eu

    dir="$PWD"

    remote_url=$(${gitBin} -C "$dir" remote get-url origin 2>/dev/null) || exit 0

    case "$remote_url" in
      https://github.com/schiphol-ac/airport-control | \
      https://github.com/schiphol-ac/airport-control.git | \
      git@github.com:schiphol-ac/airport-control | \
      git@github.com:schiphol-ac/airport-control.git)
        ;;
      *)
        exit 0
        ;;
    esac

    ${direnvBin} allow "$dir"
    _nix_direnv_force_reload=1 ${direnvBin} exec "$dir" true
  ''
