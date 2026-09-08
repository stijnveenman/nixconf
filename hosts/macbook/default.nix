{
  home-manager,
  nixpkgs,
  treehouse,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      treehouse = treehouse.packages."aarch64-darwin".default;
    };
    modules = [
      ./home.nix
      ../../modules/neovim.nix
    ];
  }
