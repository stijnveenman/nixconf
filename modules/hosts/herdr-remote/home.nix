{
  config,
  inputs,
  ...
}: let
  hm = config.flake.modules.homeManager;
in {
  flake.modules.homeManager.herdr-remote = {
    config,
    pkgs,
    ...
  }: {
    imports = [
      hm.git
      hm.nh
      hm.cli-tools
      hm.herdr
      hm.worktrunk
      hm.neovim
      hm.pi
      hm.tuicr
    ];

    my.nh.subcommand = "os";
    my.git.userEmail = "veenman.stijn@gmail.com";
    my.git.sshSigningPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEYvT8ozLHuscXbK/sMYxiyJwKqf0pkw42lpJOnyajY";

    home.username = "herdr-remote";
    home.homeDirectory = "/home/herdr-remote";
    home.stateVersion = "26.05";

    # live checkout so nvim/pi config dirs are writable symlinks, not store paths
    my.nixconf.liveRepoPath = "${config.home.homeDirectory}/nixconf";

    programs.bash.enable = true;
    programs.direnv.enable = true;
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
      pkgs.alejandra
      pkgs.openssh
      pkgs.xclip
    ];
  };
}
