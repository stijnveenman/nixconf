{
  config,
  lib,
  pkgs,
}:
pkgs.writeShellScript "treehouse-airport-control-post-create" ''
  set -eu

  dir="$PWD"
  ${lib.getExe config.programs.direnv.package} allow "$dir"
  _nix_direnv_force_reload=1 ${lib.getExe config.programs.direnv.package} exec "$dir" true
''
