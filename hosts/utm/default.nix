{
  home-manager,
  nixpkgs,
  ...
} @ inputs:
nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    ./configuration.nix
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.stiixxy = import ./home.nix inputs;
    }
  ];
}
