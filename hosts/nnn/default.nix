{
  home-manager,
  niri,
  nixpkgs,
  treehouse,
  ...
}:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./configuration.nix
    niri.nixosModules.niri
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        treehouse = treehouse.packages."x86_64-linux".default;
      };
    }
    ./home.nix
  ];
}
