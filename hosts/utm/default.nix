{
  home-manager,
  niri,
  nixpkgs,
  ...
} @ inputs:
nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    home-manager.nixosModules.home-manager
    niri.nixosModules.niri
    ./configuration.nix
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
    ./home.nix
  ];
}
