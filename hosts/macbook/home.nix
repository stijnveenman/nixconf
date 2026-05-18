{pkgs, ...}: {
  nixpkgs.config.allowUnfree = true;

  home.username = "sv";
  home.homeDirectory = "/Users/sv";

  home.stateVersion = "24.05";

  home.sessionVariables = {
    RUSH_PARALLELISM = "60%";
    PC_HIDE_DISABLED_PROC = "1";
  };

  programs.git.userEmail = "stijn.veenman@schiphol.nl";

  home.packages = [
    pkgs._1password-cli

    # Utils
    pkgs.jless
    pkgs.ripgrep
    pkgs.jq
    pkgs.fzf

    # formatting
    pkgs.nixd
    pkgs.alejandra
  ];

  programs.zsh = {
    shellAliases = {
      ri = "rush install";
      rb = "rush build";
      rbt = "rush build --to";

      ac = "cd ~/Documents/airport-control/";

      lg = "lazygit";
    };
  };

  programs.home-manager.enable = true;
}
