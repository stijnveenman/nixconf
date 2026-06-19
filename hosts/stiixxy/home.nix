{
  config,
  pkgs,
  ...
}: {
  home.username = "stiixxy";
  home.homeDirectory = "/home/stiixxy";

  home.stateVersion = "25.11";

  home.packages = [pkgs.nixd pkgs.alejandra pkgs.pear-desktop];

  home.sessionVariables = {
    NVIM_APPNAME = "nvim-nixconf";
  };

  home.file.".config/nvim-nixconf".source =
    config.lib.file.mkOutOfStoreSymlink
    "/home/${config.home.username}/nixconf/nvim";

  programs.home-manager.enable = true;
  programs.direnv.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
  };

  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
    };
  };

  programs.nh = {
    enable = true;
    homeFlake = "/home/${config.home.username}/nixconf";
  };

  # Omarchy Bashrc
  programs.bash = {
    enable = true;
    shellAliases = {
      c = "opencode";
    };
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
