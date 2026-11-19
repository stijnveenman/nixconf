{inputs, ...}: {
  flake.modules.homeManager.catppuccin = {
    imports = [inputs.catppuccin.homeModules.catppuccin];

    # Programs opt in with catppuccin.<program>.enable; autoEnable would
    # theme every supported program.
    catppuccin = {
      enable = true;
      autoEnable = false;
      flavor = "mocha";
      accent = "blue";
    };
  };
}
