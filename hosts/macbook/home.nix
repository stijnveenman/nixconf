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

  # Inner session for /handoff, run as the SHELL of `treehouse get` so cwd is the
  # worktree (detached HEAD). Creates HANDOFF_BRANCH, then launches opencode with
  # HANDOFF_PROMPT as its initial prompt. When opencode exits, treehouse returns
  # the worktree.
  handoffInnerScript = pkgs.writeShellScript "herdr-handoff-inner" ''
    git switch -c "$HANDOFF_BRANCH" 2>/dev/null || git switch "$HANDOFF_BRANCH"
    exec ${opencodeBin} --prompt "$HANDOFF_PROMPT"
  '';

  # Startup command for a /handoff tab, launched as the tab's SHELL. Acquires a
  # treehouse worktree and runs handoffInnerScript inside it (branch + opencode).
  # Reads HANDOFF_BRANCH and HANDOFF_PROMPT from the environment (set by the
  # /handoff command via `herdr tab create --env`). Closes the tab on exit.
  handoffAgentScript = pkgs.writeShellScript "herdr-handoff-agent" ''
    err=$(mktemp)
    if ! SHELL=${handoffInnerScript} ${treehouseBin} get 2>"$err"; then
      ${herdrBin} notification show "Handoff worktree failed" --body "$(cat "$err")" --position top-right --sound request
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

  # Global /handoff opencode command. Generated by home-manager so it can bake in
  # the nix store path of handoffAgentScript. Takes a Jira ticket key or a free
  # prompt, spawns a new herdr tab with a fresh treehouse worktree + branch, and
  # starts opencode there working on the task.
  xdg.configFile."opencode/command/handoff.md".text = ''
    ---
    description: Hand off a Jira ticket or prompt to a new worktree opencode tab
    agent: build
    ---

    You are bootstrapping a **handoff**: take the task below, gather any context,
    then launch a brand-new opencode session in a fresh isolated worktree that
    starts implementing it. You are the *dispatcher*, not the implementer — do not
    start writing code in this session.

    ## Input

    The task is everything the user passed to the command:

    ```
    $ARGUMENTS
    ```

    ## Step 1 — classify the input

    Decide whether the input is a **Jira ticket** or a **free-form prompt**.

    - Treat it as a Jira ticket if it is (or contains) a Jira key of the form
      `ABC-123` (uppercase project key, hyphen, number), or a Jira URL containing
      such a key. Extract the bare key (e.g. `WILBUR-16855`).
    - Otherwise treat the whole input as a free-form prompt describing the task.

    ## Step 2 — gather context

    **If it is a Jira ticket:** load the `twg` skill and use Teamwork Graph to
    fetch the ticket, e.g. `twg jira workitem get <KEY> -o json`. Read the summary,
    description, acceptance criteria, and any linked context. Summarise this into a
    clear implementation brief. If the fetch fails, stop and report the error —
    do not spawn a tab.

    **If it is a free-form prompt:** use the prompt text directly as the brief.

    ## Step 3 — derive names

    - **branch** and **tab name**:
      - Jira ticket → both are the bare ticket key (e.g. `WILBUR-16855`).
      - Free-form → **tab name** is a terse summary of the task, at most a few
        words (e.g. `fix login redirect`); **branch** is a short kebab-case slug
        of that summary (e.g. `fix-login-redirect`).

    - **prompt**: the initial prompt the new opencode session should start with.
      - Jira ticket → the implementation brief you built in Step 2, prefixed with
        the ticket key and summary.
      - Free-form → the original prompt text.

    ## Step 4 — spawn the worktree tab

    Run this single command from the current repository (its cwd is the repo you
    are handing off from). Substitute the values you derived; keep the env var
    names exactly as shown. Pass the prompt as a single argument (mind quoting /
    newlines):

    ```sh
    ${herdrBin} tab create \
      --cwd "$(pwd)" \
      --no-focus \
      --label "<TAB_NAME>" \
      --env HANDOFF_BRANCH="<BRANCH>" \
      --env HANDOFF_PROMPT="<PROMPT>" \
      --env SHELL=${handoffAgentScript}
    ```

    This opens a new background tab (it does not steal focus) that acquires a
    treehouse worktree, creates the branch, and launches opencode with your
    prompt. The worktree returns to the pool and the tab closes when that opencode
    session exits.

    ## Step 5 — report

    Tell the user what you dispatched: the tab name, branch, whether it came from a
    Jira ticket (with the key) or a prompt, and a one-line summary of the brief.
    Do not do any of the implementation work yourself.
  '';

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
