inputs @ {
  disko,
  home-manager,
  nixpkgs,
  ...
}:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = {inherit inputs;};
  modules = [
    disko.nixosModules.disko
    home-manager.nixosModules.home-manager
    ./configuration.nix
    ./disk.nix
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {inherit inputs;};
      home-manager.users.herdr-remote = import ./home.nix;
    }
  ];
}
