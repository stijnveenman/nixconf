{
  description = "wt-start: start a pi agent in a new worktree via worktrunk and herdr";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    herdr.url = "github:herdrdev/herdr/v0.9.5";
    herdr.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    herdr,
  }: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAll (pkgs: rec {
      wt-start = pkgs.callPackage ./package.nix {
        herdr = herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      default = wt-start;
    });
    devShells = forAll (pkgs: {
      default = pkgs.mkShell {packages = [pkgs.cargo pkgs.rustc];};
    });
  };
}
