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

  # Build the plugin with absolute paths for Herdr's restricted environment.
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

  # Cycle through agents by attention priority: blocked, done, then idle.
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
    pkgs.gum
  ];

  home.file.".config/treehouse/config.toml".text = ''
    max_trees = 12
  '';

  home.file.".config/herdr/plugins/threehouse".source = treehousePlugin;

  # Plugin registration is imperative and path-based.
  home.activation.herdrTreehousePlugin = lib.hm.dag.entryAfter ["linkGeneration"] ''
    PLUGIN_DIR="${config.home.homeDirectory}/.config/herdr/plugins/threehouse"
    run ${herdrBin} plugin unlink threehouse.pool >/dev/null 2>&1 || true
    run ${herdrBin} plugin link "$PLUGIN_DIR" >/dev/null 2>&1 || true
    run ${herdrBin} plugin enable threehouse.pool >/dev/null 2>&1 || true
  '';

  programs.herdr = {
    enable = true;
    package = herdr;
    settings = {
      onboarding = false;

      theme.name = "gruvbox";

      theme.custom = {
        active_row_bg = "#665c54";
        selection_bg = "#665c54";
      };

      keys.prefix = "ctrl+space";

      keys.goto = "prefix+space";

      keys.previous_workspace = "prefix+[";
      keys.next_workspace = "prefix+]";
      keys.switch_workspace = "prefix+shift+1..9";

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
          key = "prefix+o";
          type = "shell";
          command = "${nextAgentScript}";
          description = "next agent needing attention";
        }

        # smart-splits is cloned at runtime, so link its plugin once:
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
        status_indicators = "symbols";
        toast.delivery = "herdr";

        prompt_new_tab_name = false;
      };
    };
  };
}
