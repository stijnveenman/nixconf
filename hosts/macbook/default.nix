{
  home-manager,
  nixpkgs,
  worktrunk,
  ...
}: let
  pkgs = nixpkgs.legacyPackages."aarch64-darwin";
in
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit worktrunk;
    };
    modules = [
      ./home.nix
      ../../modules/neovim.nix
    ];
  }
