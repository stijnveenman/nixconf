{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/git.nix
    ../../modules/cli-tools.nix
    ../../modules/herdr
    ../../modules/neovim.nix
    ../../modules/pi.nix
  ];

  my.git.userEmail = "veenman.stijn@gmail.com";

  programs.git = {
    signing = {
      format = "ssh";
      key = lib.mkForce "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
    settings.gpg.ssh = {
      program = lib.getExe' pkgs.openssh "ssh-keygen";
      allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
    };
  };

  xdg.configFile."git/allowed_signers".text = ''
    ${config.my.git.userEmail} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEYvT8ozLHuscXbK/sMYxiyJwKqf0pkw42lpJOnyajY
  '';

  home.username = "herdr-remote";
  home.homeDirectory = "/home/herdr-remote";
  home.stateVersion = "26.05";

  # live checkout so nvim/pi config dirs are writable symlinks, not store paths
  my.nixconf.liveRepoPath = "${config.home.homeDirectory}/nixconf";

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
