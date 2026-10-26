{
  lib,
  pkgs,
  workmux,
}: let
  workmuxPackage = workmux.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workmuxExe = lib.getExe' workmuxPackage "workmux";
in
  # Wrapper for tmux-tpad commands: opt the tpad session out of the workmux
  # sidebar, then run the real command in its place.
  pkgs.writeShellScript "tpad-run" ''
    ${workmuxExe} sidebar --session off >/dev/null 2>&1 || true
    exec "$@"
  ''
