{
  # Graphical sudo password prompt for tools without a TTY (e.g. agents).
  flake.modules.homeManager.askpass = {
    config,
    lib,
    pkgs,
    ...
  }: let
    zenity = lib.getExe pkgs.zenity;

    askpass = pkgs.writeShellScript "askpass" ''
      zenity=${lib.escapeShellArg zenity}
      ${builtins.readFile ./scripts/askpass.sh}
    '';
  in {
    home.file.".local/bin/askpass".source = askpass;

    home.sessionVariables.NH_SUDO_ASKPASS = "${config.home.homeDirectory}/.local/bin/askpass";
  };
}
