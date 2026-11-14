{
  lib,
  pkgs,
  ...
}: let
  zenity = lib.getExe pkgs.zenity;
in
  pkgs.writeShellScript "askpass" ''
    zenity=${lib.escapeShellArg zenity}
    ${builtins.readFile ./askpass.sh}
  ''
