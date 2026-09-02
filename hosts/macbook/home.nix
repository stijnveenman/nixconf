{
  pkgs,
  lib,
  config,
  treehouse,
  ...
}: let
  # Absolute binary paths. herdr (and its panes/command keybinds) inherits the
  # GUI/launchd environment via Ghostty, which does not include the nix profile
  # on PATH, so keybind commands must reference binaries by absolute path.
  treehouseBin = lib.getExe treehouse;
  opencodeBin = lib.getExe config.programs.opencode.package;
  lazygitBin = lib.getExe config.programs.lazygit.package;
in {
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

    # agent runtime + worktree pool
    treehouse

    # fonts
    pkgs.nerd-fonts.jetbrains-mono
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
      o = "opencode";

      h = "herdr";
      th = "treehouse";
    };
  };

  programs.home-manager.enable = true;

  # treehouse user-level config (~/.config/treehouse/config.toml).
  # Per-repo treehouse.toml files (committed per project) still override this.
  home.file.".config/treehouse/config.toml".text = ''
    # Maximum number of worktrees kept in each per-repo pool.
    max_trees = 8

    # root is left unset -> defaults to ~/.treehouse
    # base_branch is left unset -> inferred per-repo (origin/HEAD, etc.)
    # vcs is left unset -> git (default)
  '';

  programs.herdr = {
    enable = true;
    settings = {
      # Skip the first-run onboarding wizard (config is managed here).
      onboarding = false;

      theme.name = "gruvbox";

      keys.prefix = "ctrl+space";

      keys.command = [
        {
          key = "prefix+g";
          type = "popup";
          command = lazygitBin;
          description = "lazygit";
          width = "80%";
          height = "80%";
        }
        {
          # Lease a warm treehouse worktree, open opencode in it, and return
          # the worktree to the pool when opencode exits. Absolute paths because
          # herdr keybind commands run via /bin/sh -c without the nix PATH.
          key = "prefix+a";
          type = "pane";
          command = ''d=$(${treehouseBin} get --lease) && cd "$d" && ${opencodeBin}; ${treehouseBin} return --force "$d"'';
          description = "worktree + opencode";
        }
      ];

      ui = {
        # Distinguish agent state by shape as well as colour.
        status_indicators = "symbols";
        toast.delivery = "herdr";

        # Don't prompt for a tab name on creation; use the default.
        prompt_new_tab_name = false;
      };
    };
  };

  programs.ghostty = {
    enable = true;
    # nixpkgs ghostty is Linux-only; on aarch64-darwin install the app via
    # `brew install --cask ghostty`. Home-manager manages config only here.
    package = null;
    enableZshIntegration = true;
    settings = {
      theme = "Gruvbox Dark";

      font-family = "JetBrainsMono Nerd Font";
      font-size = 13;

      # Treat the macOS Option key as Alt/Meta so terminal keybinds work.
      macos-option-as-alt = true;

      # Launch herdr in the first Ghostty surface on startup. New tabs/windows
      # remain plain shells; quitting herdr closes that first surface.
      # Use the absolute herdr binary with `direct:` so Ghostty runs it without
      # shell wrapping (which mangles the argv) and without relying on the GUI
      # launchd PATH.
      initial-command = "direct:${lib.getExe config.programs.herdr.package}";

      # Fully quit Ghostty when the last window closes so reopening starts a
      # fresh process, which re-runs initial-command (herdr) above.
      quit-after-last-window-closed = true;
    };
  };

  programs.gh = {
    enable = true;
    extensions = [pkgs.gh-poi];
  };

  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
    };
    tui = {
      theme = "gruvbox";
      attention = {
        enabled = true;
        notifications = true;
        sound = false;
      };
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    settings.user.name = "Stijn Veenman";
    settings.user.email = "stijn.veenman@schiphol.nl";
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

      # Disable all background tasks for maximum speed / minimal git activity.
      git.autoFetch = false; # no periodic `git fetch`
      git.fetchAll = false; # don't pass --all to git fetch
      git.autoRefresh = false; # no periodic file/submodule refresh
      git.autoDetectExternalChanges = false; # no periodic repo polling
      update.method = "never"; # no periodic update checks

      gui = {
        branchColors = {
          config = "#11aaff";
        };

        # Remove the submodules and tags panels.
        sidePanels = [
          ["status"]
          ["files" "worktrees"]
          ["branches" "remotes"]
          ["commits" "reflog"]
          ["stash"]
        ];
      };
    };
  };
}
