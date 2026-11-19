{inputs, ...}: {
  flake.modules.homeManager.gh-dash = {
    imports = [inputs.catppuccin.homeModules.catppuccin];

    # Only gh-dash for now; autoEnable would theme every supported program.
    catppuccin = {
      enable = true;
      autoEnable = false;
      flavor = "mocha";
      accent = "blue";
      gh-dash.enable = true;
    };

    programs.gh-dash.enable = true;
  };
}
