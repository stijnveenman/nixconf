{inputs, ...}: {
  flake.modules.homeManager.catppuccin = {
    # Program modules each import this one; the key makes the module system
    # import it (and catppuccin/nix's module) only once.
    key = "nixconf#homeManager.catppuccin";
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
