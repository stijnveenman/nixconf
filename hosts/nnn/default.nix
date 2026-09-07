{
  herdr,
  home-manager,
  niri,
  nixpkgs,
  treehouse,
  ...
}: let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
in
  nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      ./configuration.nix
      niri.nixosModules.niri
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          herdr = pkgs.callPackage "${herdr}/nix/package.nix" {};
          treehouse = treehouse.packages."x86_64-linux".default;
        };
      }
      ./home.nix
    ];
  }
