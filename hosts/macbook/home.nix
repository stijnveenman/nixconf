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
  lazygitBin = lib.getExe config.programs.lazygit.package;
  herdrBin = lib.getExe config.programs.herdr.package;
  jqBin = lib.getExe pkgs.jq;
  gumBin = lib.getExe pkgs.gum;

  # The treehouse.pool herdr plugin. A popup (gum) prompts for a name/base,
  # leases a worktree from the treehouse pool, opens it as a herdr workspace,
  # and returns the lease when the workspace closes. Built into the store with
  # absolute binary paths substituted, so no reliance on PATH in herdr's
  # launchd/Ghostty environment. See herdr/threehouse/ for the sources.
  treehousePluginSrc = ../../herdr/threehouse;
  treehousePlugin = pkgs.runCommand "herdr-plugin-threehouse" {} ''
    mkdir -p "$out"
    cp ${treehousePluginSrc}/lib.sh "$out/lib.sh"
    cp ${treehousePluginSrc}/new.sh "$out/new.sh"
    cp ${treehousePluginSrc}/return.sh "$out/return.sh"
    cp ${treehousePluginSrc}/reconcile.sh "$out/reconcile.sh"

    substitute ${treehousePluginSrc}/herdr-plugin.toml.in "$out/herdr-plugin.toml" \
      --replace-fail '@BASH@' '${lib.getExe pkgs.bash}' \
      --replace-fail '@ROOT@' "$out"

    for f in lib.sh new.sh return.sh reconcile.sh; do
      substituteInPlace "$out/$f" \
        --replace-quiet '@HERDR@' '${herdrBin}' \
        --replace-quiet '@TREEHOUSE@' '${lib.getExe treehouse}' \
        --replace-quiet '@JQ@' '${jqBin}' \
        --replace-quiet '@GUM@' '${gumBin}' \
        --replace-quiet '@TOOLPATH@' '${lib.makeBinPath [config.programs.git.package pkgs.coreutils pkgs.gnugrep pkgs.gnused]}'
      chmod +x "$out/$f"
    done
  '';

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

  # Local user bins (e.g. twg, used by the /handoff command) on PATH.
  home.sessionPath = ["$HOME/.local/bin"];

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
    pkgs.gum # pretty popup prompts for the treehouse.pool herdr plugin

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
    max_trees = 12

    # root is left unset -> defaults to ~/.treehouse
    # base_branch is left unset -> inferred per-repo (origin/HEAD, etc.)
    # vcs is left unset -> git (default)
  '';

  # Materialize the treehouse.pool herdr plugin (built in the store with
  # absolute bin paths) into a stable path, then link + enable it with herdr on
  # activation. herdr plugin registration is imperative and path-based, so this
  # activation step keeps it in sync idempotently on every switch.
  home.file.".config/herdr/plugins/threehouse".source = treehousePlugin;

  home.activation.herdrTreehousePlugin = lib.hm.dag.entryAfter ["linkGeneration"] ''
    PLUGIN_DIR="${config.home.homeDirectory}/.config/herdr/plugins/threehouse"
    # link is idempotent-ish: unlink first (ignore errors) then relink + enable.
    run ${herdrBin} plugin unlink threehouse.pool >/dev/null 2>&1 || true
    run ${herdrBin} plugin link "$PLUGIN_DIR" >/dev/null 2>&1 || true
    run ${herdrBin} plugin enable threehouse.pool >/dev/null 2>&1 || true
  '';

  programs.herdr = {
    enable = true;
    settings = {
      # Skip the first-run onboarding wizard (config is managed here).
      onboarding = false;

      theme.name = "gruvbox";

      keys.prefix = "ctrl+space";

      # Session navigator on leader-space (default is prefix+g). herdr does not
      # support double-prefix chords, so this is the closest "tap leader then
      # space" navigator.
      keys.goto = "prefix+space";

      # Move between workspaces (worktrees are workspaces too):
      #   leader [ / ]        -> previous / next workspace
      #   leader shift+1..9   -> jump directly to workspace 1-9
      # All three actions are unset by default, so nothing is overwritten.
      keys.previous_workspace = "prefix+[";
      keys.next_workspace = "prefix+]";
      keys.switch_workspace = "prefix+shift+1..9";

      keys.command = [
        {
          key = "ctrl+g";
          type = "popup";
          command = lazygitBin;
          description = "lazygit";
          width = "80%";
          height = "80%";
        }
        {
          # Open a new pooled worktree as a workspace (treehouse.pool plugin).
          # Popup prompts for name + base, leases from the treehouse pool, and
          # opens it as a herdr workspace. A popup pane is opened via
          # `plugin pane open` (not a plugin_action), so this is a shell keybind.
          key = "prefix+shift+g";
          type = "shell";
          command = "${herdrBin} plugin pane open --plugin threehouse.pool --entrypoint new";
          description = "new pooled workspace";
        }
        {
          # Jump to the next agent needing attention (blocked > done > idle).
          # See nextAgentScript above.
          key = "prefix+o";
          type = "shell";
          command = "${nextAgentScript}";
          description = "next agent needing attention";
        }

        # Seamless ctrl+hjkl navigation between neovim splits and herdr panes,
        # via smart-splits.nvim's bundled herdr plugin (tmux-navigator style).
        # These forward the key to the focused pane when it runs vim/neovim (so
        # vim moves its own splits, crossing pane boundaries at edges), and move
        # herdr focus directly otherwise. Shell defaults like ctrl+l / ctrl+h
        # still work at window edges via the plugin's passthrough.
        #
        # Requires a ONE-TIME imperative link to smart-splits' checkout, which
        # lazy.nvim clones at runtime (path is not known to nix):
        #   herdr plugin link ~/.local/share/nvim-nixconf/lazy/smart-splits.nvim
        #   herdr server reload-config
        {
          key = "ctrl+h";
          type = "plugin_action";
          command = "smart-splits.nvim.left";
          description = "navigate left (vim/herdr)";
        }
        {
          key = "ctrl+j";
          type = "plugin_action";
          command = "smart-splits.nvim.down";
          description = "navigate down (vim/herdr)";
        }
        {
          key = "ctrl+k";
          type = "plugin_action";
          command = "smart-splits.nvim.up";
          description = "navigate up (vim/herdr)";
        }
        {
          key = "ctrl+l";
          type = "plugin_action";
          command = "smart-splits.nvim.right";
          description = "navigate right (vim/herdr)";
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
