# x86-64 NixOS VM for remote Herdr sessions. See README.md before installing.
{
  config,
  inputs,
  ...
}: let
  nixos = config.flake.modules.nixos;
in {
  flake.nixosConfigurations.herdr-remote = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      nixos.herdr-remote
      nixos.herdr-remote-disk
      nixos.attic-cache
      nixos.home-manager
      {home-manager.users.herdr-remote = config.flake.modules.homeManager.herdr-remote;}
    ];
  };
}
