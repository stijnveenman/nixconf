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
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    oh-my-zsh = {
      enable = true;
      plugins = ["git"];
      theme = "robbyrussell";
    };
  };
  home.sessionPath = ["$HOME/.local/bin"];
  home.packages = [
    inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.claude-code
    pkgs.openssh
    pkgs.xclip
  ];
}
