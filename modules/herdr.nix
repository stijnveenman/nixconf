{
  pkgs,
  lib,
  config,
  treehouse,
  ...
}: let
  # Absolute binary paths. herdr keybind/command/pane processes do not
  # necessarily inherit the nix profile on PATH (e.g. launched from Ghostty's
  # macOS launchd env, or any Nix session where PATH is not assumed), so keybind
  # commands must reference binaries by absolute store path.
  lazygitBin = lib.getExe config.programs.lazygit.package;
  herdrBin = lib.getExe config.programs.herdr.package;
  jqBin = lib.getExe pkgs.jq;
  gumBin = lib.getExe pkgs.gum;

  # Interactive shell used to wrap lazygit (see lazygitLoginScript). herdr runs
  # zsh on the macbook and bash on nnn; pick whichever this host enables so the
  # wrapper inherits that shell's interactive PATH.
  interactiveShell =
    if config.programs.zsh.enable
    then config.programs.zsh.package
    else config.programs.bash.package;

  # Launch lazygit through an interactive shell so its git/commit-hook
  # subprocesses inherit the same PATH as a normal terminal (nix profile,
  # direnv, ...). herdr popups may run in an environment that does not put the
  # nix profile on PATH, so a repo pre-commit hook such as
  # `direnv exec . rush prettier` otherwise fails to find direnv (direnv then
  # supplies rush/node from the repo's .envrc). An interactive (-i) shell is
  # required, not a login (-l) one: home-manager gates its session vars on
  # `[[ ! -o login ]]` in the shell rc, so a login shell skips them. `exec`
  # replaces the shell so lazygit stays the popup foreground.
  #
  # herdr popup processes do NOT start in the focused pane's cwd — they start in
  # a fixed base (e.g. the workspace/server root), so from a worktree pane
  # lazygit would otherwise open the project root rather than the worktree (and
  # git-crypt/git would then operate on the wrong tree). Resolve the focused
  # pane's foreground cwd from HERDR_PLUGIN_CONTEXT_JSON (falling back to
  # `herdr pane current`) and cd into it before launching lazygit, mirroring the
  # treehouse plugin's repo-resolution logic.
  lazygitLoginScript = pkgs.writeShellScript "herdr-lazygit" ''
    set -u
    target=""
    if [ -n "''${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
      target="$(
        printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" \
          | ${jqBin} -r '(.pane.foreground_cwd // .pane.cwd // .workspace.cwd // empty)' 2>/dev/null || true
      )"
    fi
    if [ -z "$target" ]; then
      target="$(
        ${herdrBin} pane current 2>/dev/null \
          | ${jqBin} -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' 2>/dev/null || true
      )"
    fi
    if [ -n "$target" ] && [ -d "$target" ]; then
      cd "$target" || true
    fi
    exec ${lib.getExe interactiveShell} -i -c 'exec ${lazygitBin}'
  '';

  # The treehouse.pool herdr plugin. A popup (gum) prompts for a name/base,
  # leases a worktree from the treehouse pool, opens it as a herdr workspace,
  # and returns the lease when the workspace closes. Built into the store with
  # absolute binary paths substituted, so no reliance on PATH in herdr's
  # environment. See herdr/threehouse/ for the sources.
  treehousePluginSrc = ../herdr/threehouse;
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
  home.packages = [
    treehouse
    pkgs.gum # pretty popup prompts for the treehouse.pool herdr plugin
  ];

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
          # lazygit via an interactive shell so its git/commit-hook subprocesses
          # inherit the full interactive PATH (nix profile, direnv, ...).
          # Launching the bare binary from herdr's env lacks the nix profile on
          # PATH, so hooks like `direnv exec . rush prettier` fail to find
          # direnv. See lazygitLoginScript for why -i (not -l).
          key = "ctrl+g";
          type = "popup";
          command = "${lazygitLoginScript}";
          description = "lazygit";
          width = "80%";
          height = "80%";
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
}
