{
  self,
  inputs,
  ...
}: {
  flake.homeConfigurations.stiixxy =
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {system = "x86_64-linux";};
      modules = [
        self.homeModules.nh
        {
          home.username = "stiixxy";
          home.homeDirectory = "/home/stiixxy/";
          home.stateVersion = "25.11";

          programs.bash = {
            enable = true;
            bashrcExtra = "
# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

eval \"$(direnv hook bash)\"

removebg() {
  magick \"$1\" -fuzz 10% -transparant \"$2:white\" \"$1\"
}
          ";
          };
        }
      ];
    };

  flake.homeModules.nh = {
    programs.nh = {
      enable = true;
      homeFlake = "/home/stiixxy/nixconf";
    };
  };
}
