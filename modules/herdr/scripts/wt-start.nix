{
  inputs,
  lib,
  pkgs,
  ...
}: let
  wt = lib.getExe pkgs.worktrunk;
  herdr = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  git = lib.getExe pkgs.git;
  jq = lib.getExe pkgs.jq;
in
  pkgs.writeShellScript "wt-start" ''
    wt=${lib.escapeShellArg wt}
    herdr=${lib.escapeShellArg herdr}
    git=${lib.escapeShellArg git}
    jq=${lib.escapeShellArg jq}
    ${builtins.readFile ./wt-start.sh}
  ''
