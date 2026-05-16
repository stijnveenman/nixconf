{
  config,
  pkgs,
  ...
}: {
  imports = [./nh.nix];

  home.username = "stiixxy";
  home.homeDirectory = "/home/stiixxy";

  home.stateVersion = "25.11";

  home.packages = [pkgs.nixd pkgs.alejandra];

  programs.home-manager.enable = true;
  programs.direnv.enable = true;

  # Omarchy Bashrc
  programs.bash = {
    enable = true;
    bashrcExtra = "
# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

removebg() {
  magick \"$1\" -fuzz 10% -transparant \"$2:white\" \"$1\"
}
          ";
  };
}
