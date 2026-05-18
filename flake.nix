{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: {
    homeConfigurations."stiixxy" = import ./hosts/stiixxy inputs;
    homeConfigurations."sv" = import ./hosts/macbook inputs;
  };
}
