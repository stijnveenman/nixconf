# Settings for home-manager's NixOS module, shared by the NixOS hosts. Hosts
# import `inputs.home-manager.nixosModules.home-manager` themselves.
{
  flake.modules.nixos.home-manager = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
  };
}
