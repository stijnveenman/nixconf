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
  herdrBin = lib.getExe config.programs.herdr.package;
  jqBin = lib.getExe pkgs.jq;

  # Jump to the next agent needing attention, ranked by status priority
  # (blocked, then done, then idle). Reimplements martin-ro/herdr-next-agent as
  # a native keybind (no Python/plugin install). If the focused pane is in the
  # ranked set, jumps to the next one so repeated presses cycle through all;
  # toasts when nothing needs attention. herdr/jq by absolute path (keybind env
  # lacks the nix profile on PATH).
  nextAgentScript = pkgs.writeShellScript "herdr-next-agent" ''
    agents=$(${herdrBin} agent list) || exit 1

    target=$(printf '%s' "$agents" | ${jqBin} -r '
      ["blocked","done","idle"] as $prio
      | .result.agents
      | map(.rank = (.agent_status as $s | $prio | index($s)))
      | map(select(.rank != null))
      | sort_by(.rank)
      | . as $ranked
      | ($ranked | map(.focused) | index(true)) as $cur
      | if ($ranked | length) == 0 then ""
        elif $cur == null then $ranked[0].pane_id
        else $ranked[(($cur + 1) % ($ranked | length))].pane_id
        end
    ')

    if [ -z "$target" ]; then
      ${herdrBin} notification show "No agent needs attention" --position top-right >/dev/null 2>&1
      exit 0
    fi

    ${herdrBin} agent focus "$target" >/dev/null 2>&1
  '';

  # Startup command for the "worktree + opencode" tab, launched as the tab's
  # SHELL. `treehouse get` acquires a worktree, opens a subshell in it, and
  # auto-returns it when that subshell exits; we point the subshell at opencode
  # via SHELL, so opencode is the session. On exit, close the tab (via
  # HERDR_TAB_ID provided by herdr). Runs in a login shell + direnv, so project
  # devshell tools (e.g. git-crypt) are on PATH.
  #
  # git-crypt repos should set `filter.git-crypt.required = false` locally so a
  # worktree checkout leaves files encrypted instead of aborting.
  worktreeAgentScript = pkgs.writeShellScript "herdr-worktree-agent" ''
    err=$(mktemp)
    if ! SHELL=${opencodeBin} ${treehouseBin} get 2>"$err"; then
      ${herdrBin} notification show "Worktree acquire failed" --body "$(cat "$err")" --position top-right --sound request
    fi
    rm -f "$err"
    ${herdrBin} tab close "$HERDR_TAB_ID"
  '';
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
      x = "opencode";

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
          # Open opencode in a fresh treehouse worktree, in a new tab rooted in
          # the triggering pane's repo (HERDR_ACTIVE_PANE_CWD). The tab launches
          # worktreeAgentScript as its shell (via --env SHELL).
          key = "prefix+a";
          type = "shell";
          command = ''
            src="''${HERDR_ACTIVE_PANE_CWD:-$HOME}"
            ${herdrBin} tab create --cwd "$src" --focus --env SHELL=${worktreeAgentScript} || \
              ${herdrBin} notification show "New worktree tab failed" --position top-right --sound request >/dev/null 2>&1
          '';
          description = "worktree + opencode (new tab)";
        }
        {
          # Jump to the next agent needing attention (blocked > done > idle).
          # See nextAgentScript above.
          key = "prefix+o";
          type = "shell";
          command = "${nextAgentScript}";
          description = "next agent needing attention";
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

      font-family = "JetBrainsMono Nerd Font Mono";
      font-size = 12;
      # Disable programming ligatures (e.g. != stays as two glyphs).
      font-feature = ["-calt" "-liga" "-dlig"];

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
