{
  pkgs,
  lib,
  config,
  herdr,
  treehouse,
  ...
}: let
  # Herdr processes may not inherit the Nix profile on PATH.
  lazygitBin = lib.getExe config.programs.lazygit.package;
  herdrBin = lib.getExe config.programs.herdr.package;
  jqBin = lib.getExe pkgs.jq;
  gumBin = lib.getExe pkgs.gum;

  interactiveShell =
    if config.programs.zsh.enable
    then config.programs.zsh.package
    else config.programs.bash.package;

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
    package = herdr;
    settings = {
      # Skip the first-run onboarding wizard (config is managed here).
      onboarding = false;

      theme.name = "gruvbox";

      # Bump the contrast of the selected sidebar row. Gruvbox's default
      # selection background sits close to the sidebar background and is hard
      # to pick out; use a lighter gruvbox gray so the highlighted row reads
      # clearly against the dark sidebar.
      theme.custom = {
        active_row_bg = "#665c54";
        selection_bg = "#665c54";
      };

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

      # Open an existing Git worktree from the selected workspace. Native
      # builtin action (unset by default), bound to leader ctrl+shift+g.
      keys.open_worktree = "prefix+ctrl+shift+g";

      keys.command = [
        {
          # Use an interactive shell so hooks inherit the normal terminal PATH.
          key = "ctrl+g";
          type = "pane";
          command = "${lib.getExe interactiveShell} -i -c 'exec ${lazygitBin}'";
          description = "lazygit";
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
