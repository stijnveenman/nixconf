# Standalone home-manager on the work MacBook (user `sv`).
{
  config,
  inputs,
  ...
}: let
  hm = config.flake.modules.homeManager;
in {
  flake.homeConfigurations.sv = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages."aarch64-darwin";
    modules = [
      hm.macbook
      hm.neovim
    ];
  };
}
