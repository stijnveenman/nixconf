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
    plugins = [inputs.smart-splits.outPath];
    toml = pkgs.formats.toml {};
    popupSize = "80%";

    bottomPane = pkgs.writeShellScript "herdr-bottom-pane" ''
      export PATH=${lib.makeBinPath [herdr pkgs.jq]}:$PATH
      ${builtins.readFile ./scripts/bottom-pane.sh}
    '';

    wtStart = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.wt-start;

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
        command = [
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
            key = "prefix+shift+g";
            type = "shell";
            command = "${bottomPane} ${lib.getExe wtStart}";
            description = "wt start";
          }
          {
            key = "prefix+shift+d";
            type = "shell";
            command = "${bottomPane} ${config.my.worktrunk.safeRemove}";
            description = "wt remove";
          }
          {
            key = "ctrl+minus";
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
  };
}
