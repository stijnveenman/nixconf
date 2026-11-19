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
    git = lib.getExe pkgs.git;
    jq = lib.getExe pkgs.jq;
    lazygit = lib.getExe pkgs.lazygit;
    cksum = lib.getExe' pkgs.coreutils "cksum";

    inherit (config.lib.herdr) pluginEntry action;

    settings = {
      onboarding = false;
      ui.prompt_new_tab_name = false;
      keys = {
        prefix = "ctrl+a";
        goto = "prefix+g";
        workspace_picker = ["prefix+w" "prefix+space"];
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
            command = "${lazygitSession}";
            description = "lazygit (nested session per worktree)";
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
      # Lets the lazygit popup attach a nested session.
      experimental.allow_nested = true;
    };

    # Config for the nested lazygit sessions: no sidebar, and no bindings that
    # would shadow lazygit keys (ctrl+j/k move commits) or reopen the popup.
    nestedSettings = {
      inherit (settings) onboarding theme experimental;
      ui =
        settings.ui
        // {
          sidebar_start_collapsed = true;
          sidebar_collapsed_mode = "hidden";
        };
      keys = {inherit (settings.keys) prefix;};
    };
    nestedConfig = toml.generate "herdr-nested-config.toml" nestedSettings;

    lazygitSession = pkgs.writeShellScript "herdr-lazygit-session" ''
      herdr=${lib.escapeShellArg (lib.getExe herdr)}
      git=${lib.escapeShellArg git}
      jq=${lib.escapeShellArg jq}
      lazygit=${lib.escapeShellArg lazygit}
      cksum=${lib.escapeShellArg cksum}
      nested_config=${lib.escapeShellArg nestedConfig}
      ${builtins.readFile ./scripts/lazygit-session.sh}
    '';
  in {
    imports = [flakeModules.homeManager.herdr-lib];

    home.packages = [herdr];

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
