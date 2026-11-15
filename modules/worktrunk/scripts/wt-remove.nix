{
  inputs,
  lib,
  pkgs,
  ...
}: let
  herdr = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  jq = lib.getExe pkgs.jq;
in
  pkgs.writeShellScript "wt-remove-herdr" ''
    herdr=${lib.escapeShellArg herdr}
    jq=${lib.escapeShellArg jq}
    ${builtins.readFile ./wt-remove.sh}
  ''
