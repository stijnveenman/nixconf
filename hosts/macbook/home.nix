{
  pkgs,
  config,
  ...
}: {
  nixpkgs.config.allowUnfree = true;

  home.username = "sv";
  home.homeDirectory = "/Users/sv";

  home.stateVersion = "24.05";

  programs.nh = {
    enable = true;
    homeFlake = "/Users/${config.home.username}/Documents/nixconf";
  };

  home.sessionVariables = {
    RUSH_PARALLELISM = "60%";
    PC_HIDE_DISABLED_PROC = "1";
  };

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
    enable = true;
    enableCompletion = true;
    plugins = [
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "chisui";
          repo = "zsh-nix-shell";
          rev = "v0.8.0";
          sha256 = "1lzrn0n4fxfcgg65v0qhnj7wnybybqzs4adz7xsrkgmcsr0ii8b7";
        };
      }
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
      ];
      theme = "robbyrussell";
    };

    shellAliases = {
      ri = "rush install";
      rb = "rush build";
      rbt = "rush build --to";

      ac = "cd ~/Documents/airport-control/";

      lg = "lazygit";
    };
  };

  programs.home-manager.enable = true;

  programs.gh = {
    enable = true;
    extensions = [pkgs.gh-poi];
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    userName = "Stijn Veenman";
    userEmail = "stijn.veenman@schiphol.nl";
    signing = {
      signByDefault = true;
      # autodetect based on commit
      key = null;
    };
  };

  programs.atuin = {
    enable = true;
    flags = ["--disable-up-arrow"];
    settings = {
      inline_height = 15;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      quitOnTopLevelReturn = true;
      git.overrideGpg = false;
      git.autoFetch = false;

      gui = {
        branchColors = {
          config = "#11aaff";
        };
      };
    };
  };
}
