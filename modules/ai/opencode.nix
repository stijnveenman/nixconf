{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.opencode = {config, ...}: {
    imports = [flakeModules.homeManager.repo];

    programs.opencode = {
      enable = true;
      settings = {
        autoupdate = false;
        permission = {
          bash."git *" = "allow";
        };
      };
      cli = {
        theme.name = "catppuccin";
        attention = {
          notifications = true;
          sound = false;
        };
      };
      validateFiles.cli = true;
    };

    home.file.".config/opencode/skill".source = config.lib.nixconf.source "programs/opencode/skill";
    home.file.".config/opencode/command".source = config.lib.nixconf.source "programs/opencode/command";
  };
}
