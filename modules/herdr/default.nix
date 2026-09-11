{
  pkgs,
  lib,
  ...
}: let
  nextAgentScript = import ./scripts/next-agent.nix {inherit pkgs lib;};
  switchNixconfScript = import ./scripts/switch-nixconf.nix {inherit pkgs lib;};
in {
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

      keys.prefix = "ctrl+a";

      keys.previous_workspace = "prefix+[";
      keys.next_workspace = "prefix+]";

      keys.command = [
        {
          key = "ctrl+g";
          type = "shell";
          command = pkgs.writeShellScript "lazygit pane" ''
            PANE=$(herdr pane split $HERDR_PANE_ID --direction right --ratio 0.5 --focus | jq '.result.pane.pane_id' -r)
            herdr pane run $PANE 'exec ${lib.getExe pkgs.lazygit}'
          '';
          description = "lazygit";
        }
        {
          key = "prefix+k";
          command = "herdr-bar.open";
          description = "Command bar";
          type = "plugin_action";
        }
        {
          key = "prefix+ctrl+r";
          type = "popup";
          command = "${switchNixconfScript}";
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
