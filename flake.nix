{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    niri.url = "github:sodiboo/niri-flake";

    oh-my-pi.url = "github:can1357/oh-my-pi";

    treehouse.url = "github:kunchenguid/treehouse";
    treehouse.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: {
    homeConfigurations."stiixxy" = import ./hosts/stiixxy inputs;
    homeConfigurations."sv" = import ./hosts/macbook inputs;

    nixosConfigurations."nnn" = import ./hosts/nnn inputs;
  };
}
