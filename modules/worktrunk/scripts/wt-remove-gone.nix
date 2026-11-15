{
  lib,
  pkgs,
  ...
}: let
  wt = lib.getExe pkgs.worktrunk;
  git = lib.getExe pkgs.git;
  jq = lib.getExe pkgs.jq;
in
  pkgs.writeShellScript "wt-remove-gone" ''
    wt=${lib.escapeShellArg wt}
    git=${lib.escapeShellArg git}
    jq=${lib.escapeShellArg jq}
    ${builtins.readFile ./wt-remove-gone.sh}
  ''
