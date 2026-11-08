{
  inputs,
  lib,
  pkgs,
  ...
}: let
  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  plugins = [inputs.herdr-worktrunk.outPath inputs.smart-splits.outPath];
  inherit (import ./lib.nix {inherit lib;}) pluginEntry action;
  popupSize = "80%";
  settings = {
    onboarding = false;
    ui.prompt_new_tab_name = false;
    keys = {
      prefix = "ctrl+a";
      goto = ["prefix+g" "prefix+space"];
      navigate_workspace_up = ["k" "up"];
      navigate_workspace_down = ["j" "down"];
      navigate_pane_up = "ctrl+k";
      navigate_pane_down = "ctrl+j";
      command = [
        (action "prefix+shift+g" "worktrunk.open" "Worktree: switch or create from default branch")
        (action "prefix+shift+c" "worktrunk.open-current" "Worktree: switch or create from current branch")
        (action "prefix+shift+r" "worktrunk.open-with-remotes" "Worktree: switch or create including remote branches")
        (action "prefix+shift+d" "worktrunk.remove" "Worktree: remove")
        (action "prefix+shift+m" "worktrunk.merge" "Worktree: merge")
        (action "ctrl+h" "smart-splits.nvim.left" "Navigate left")
        (action "ctrl+j" "smart-splits.nvim.down" "Navigate down")
        (action "ctrl+k" "smart-splits.nvim.up" "Navigate up")
        (action "ctrl+l" "smart-splits.nvim.right" "Navigate right")
        {
          key = "ctrl+g";
          type = "popup";
          command = lib.getExe pkgs.lazygit;
          description = "lazygit";
          width = popupSize;
          height = popupSize;
        }
      ];
    };
    theme.name = "catppuccin";
  };
in {
  home.packages = [herdr pkgs.bash pkgs.fzf pkgs.git pkgs.jq pkgs.worktrunk];
  home.file.".local/bin/wt-start".source = import ./scripts/wt-start.nix {inherit inputs lib pkgs;};

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  xdg.configFile."worktrunk/config.toml".source = (pkgs.formats.toml {}).generate "worktrunk-config.toml" {
    post-remove.herdr = "${import ./scripts/wt-remove.nix {inherit inputs lib pkgs;}} {{ worktree_path }}";
  };

  xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml {}).generate "herdr-config.toml" settings;
  xdg.configFile."herdr/plugins.json".text = builtins.toJSON (map pluginEntry plugins);
  xdg.configFile."herdr/plugins/config/worktrunk/config.toml".source = (pkgs.formats.toml {}).generate "herdr-worktrunk-config.toml" {
    slugify_new_branches = true;
    picker_placement = "popup";
    popup_width = popupSize;
    popup_height = popupSize;
  };
}
