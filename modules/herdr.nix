{
  pkgs,
  lib,
  config,
  treehouse,
  ...
}: let
  # Herdr processes may not inherit the Nix profile on PATH.
  herdrBin = lib.getExe config.programs.herdr.package;
  jqBin = lib.getExe pkgs.jq;
  gumBin = lib.getExe pkgs.gum;

  interactiveShell =
    if config.programs.zsh.enable
    then config.programs.zsh.package
    else config.programs.bash.package;

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

  # Fetch the latest nixconf changes and switch the home configuration,
  # driven from the directory set through NH_HOME_FLAKE (herdr processes may
  # not inherit the Nix profile, so fall back to the macbook's flake dir).
  switchNixconfScript = pkgs.writeShellScript "herdr-switch-nixconf" ''
    set -euo pipefail

    # Set the terminal title so the popup top bar shows a friendly name.
    printf '\033]0;nixconf switch\007'

    flake_dir=''${NH_HOME_FLAKE:-/Users/sv/Documents/nixconf}

    if [ ! -d "$flake_dir" ]; then
      ${gumBin} style --foreground red "nixconf directory not found: $flake_dir"
      exit 1
    fi

    ${gumBin} style --foreground cyan "Switching nixconf from $flake_dir"
    cd "$flake_dir" || exit 1

    # Stage 1: fetch
    ${gumBin} style --foreground cyan "Fetching latest nixconf from origin main..."
    if ! git pull --ff-only origin main; then
      ${gumBin} style --foreground red "Fetch failed (diverged or no upstream?). Fix it and retry."
      read -s -n1 -p "Press any key to close..."
      exit 1
    fi

    # Stage 2: switch
    ${gumBin} style --foreground cyan "Switching nixconf home configuration..."
    if ! nh home switch "$flake_dir"; then
      ${gumBin} style --foreground red "nh home switch failed, see errors above."
      read -s -n1 -p "Press any key to close..."
      exit 1
    fi

    # Stage 3: reload herdr config so new keybindings take effect immediately.
    ${herdrBin} server reload-config >/dev/null 2>&1 || true

    ${gumBin} style --foreground green "nixconf switched successfully."
    read -s -n1 -p "Press any key to close..."
  '';
in {
  home.packages = [
    treehouse
    pkgs.gum
  ];

  home.file.".config/treehouse/config.toml".text = ''
    max_trees = 12
  '';

  programs.herdr = {
    enable = true;
    package = pkgs.herdr;
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
          type = "shell";
          command = pkgs.writeShellScript "lazygit pane" ''
            PANE=$(herdr pane split $HERDR_PANE_ID --direction right --ratio 0.5 --focus | jq '.result.pane.pane_id' -r)
            herdr pane run $PANE '${lib.getExe pkgs.lazygit} && exit'
          '';
          description = "lazygit";
        }
        {
          key = "prefix+ctrl+r";
          type = "popup";
          command = "${lib.getExe interactiveShell} -i -c 'exec ${switchNixconfScript}'";
          width = 90;
          height = 24;
          description = "fetch and switch nixconf";
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
