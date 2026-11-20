{config, ...}: let
  hm = config.flake.modules.homeManager;
in {
  flake.modules.homeManager.claude = {
    imports = [hm.agent-skills];

    home.username = "root";
    home.homeDirectory = "/root";
    home.stateVersion = "26.05";
  };
}
