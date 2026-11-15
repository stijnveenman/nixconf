# NixOS desktop (niri) with home-manager for `stiixxy`.
{
  config,
  inputs,
  ...
}: let
  nixos = config.flake.modules.nixos;
in {
  flake.nixosConfigurations.nnn = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      nixos.nnn
      inputs.niri.nixosModules.niri
      inputs.home-manager.nixosModules.home-manager
      nixos.home-manager
      {home-manager.users.stiixxy = config.flake.modules.homeManager.nnn;}
    ];
  };
}
