{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/cli-tools.nix
    ../../modules/herdr
    ../../modules/neovim.nix
    ../../modules/pi.nix
  ];

  home.username = "herdr-remote";
  home.homeDirectory = "/home/herdr-remote";
  home.stateVersion = "26.05";

  programs.bash.enable = true;
  home.sessionPath = ["$HOME/.local/bin"];
  home.packages = [
    inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.claude-code
    pkgs.gh
    pkgs.openssh
  ];
}
