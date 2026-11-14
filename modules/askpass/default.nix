{
  config,
  lib,
  pkgs,
  ...
}: {
  # Graphical sudo password prompt for tools without a TTY (e.g. agents).
  home.file.".local/bin/askpass".source = import ./scripts/askpass.nix {inherit lib pkgs;};

  home.sessionVariables.NH_SUDO_ASKPASS = "${config.home.homeDirectory}/.local/bin/askpass";
}
