{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.gh-dash = {
    imports = [flakeModules.homeManager.catppuccin];

    catppuccin.gh-dash.enable = true;

    programs.gh-dash.enable = true;
  };
}
