# Standalone home-manager on the Omarchy (Arch) laptop.
{
  config,
  inputs,
  ...
}: let
  hm = config.flake.modules.homeManager;
in {
  flake.homeConfigurations.stiixxy = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages."x86_64-linux";
    modules = [
      hm.stiixxy
      hm.neovim
      hm.opencode
      hm.nh
      hm.attic-cache
    ];
  };
}
