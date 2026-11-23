{
  config,
  inputs,
  ...
}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.herdr = {
    config,
    lib,
    pkgs,
    ...
  }: let
    herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
    plugins = [inputs.herdr-worktrunk.outPath inputs.smart-splits.outPath];
    toml = pkgs.formats.toml {};
    popupSize = "80%";

    inherit (config.lib.herdr) pluginEntry action;

    settings = {
      onboarding = false;
      ui.prompt_new_tab_name = false;
      # PR review panes report "PR #N" as their agent name (modules/ai/pr-review).
      ui.sidebar.agents.rows = [
        ["state_icon" "workspace"]
        [
          {
            token = "agent";
            rules = [
              {
                starts_with = "PR #";
                dim = true;
              }
            ];
          }
        ]
      ];
      keys = {
        prefix = "ctrl+a";
        goto = "prefix+g";
        workspace_picker = ["prefix+w" "prefix+space"];
        navigate_workspace_up = ["k" "up"];
        navigate_workspace_down = ["j" "down"];
        navigate_pane_up = "ctrl+k";
        navigate_pane_down = "ctrl+j";
        # Built-in default; frees prefix+minus for the gh-dash popup.
        split_horizontal = "";
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
          {
            key = "prefix+minus";
            type = "popup";
            command = lib.getExe pkgs.gh-dash;
            description = "gh dash";
            width = popupSize;
            height = popupSize;
          }
          {
            key = "ctrl+/";
            type = "popup";
            command = lib.getExe pkgs.zsh;
            description = "temp shell";
            width = popupSize;
            height = popupSize;
          }
        ];
      };
      theme.name = "catppuccin";
    };
  in {
    imports = [flakeModules.homeManager.herdr-lib];

    home.packages = [herdr];

    # Every new Ghostty window/tab starts in (or attaches to) the herdr session
    # instead of a bare shell. Absolute path: macOS Ghostty may lack nix PATH.
    programs.ghostty.settings.command = "${herdr}/bin/herdr";

    programs.zoxide = {
      enable = true;
      enableZshIntegration = lib.mkIf config.programs.zsh.enable true;
      enableBashIntegration = lib.mkIf config.programs.bash.enable true;
    };

    xdg.configFile."herdr/config.toml".source = toml.generate "herdr-config.toml" settings;
    xdg.configFile."herdr/plugins.json".text = builtins.toJSON (map pluginEntry plugins);
    xdg.configFile."herdr/plugins/config/worktrunk/config.toml".source = toml.generate "herdr-worktrunk-config.toml" {
      slugify_new_branches = true;
      picker_placement = "popup";
      popup_width = popupSize;
      popup_height = popupSize;
    };
  };
}
