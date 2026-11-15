{
  config,
  inputs,
  ...
}: let
  hm = config.flake.modules.homeManager;
in {
  flake.modules.homeManager.nnn = {pkgs, ...}: {
    home.stateVersion = "26.05";

    imports = [
      hm.neovim
      hm.git
      hm.nh
      hm.cli-tools
      hm.tuicr
      hm.ghostty
      hm.opencode
      hm.pi
      hm.herdr
      hm.worktrunk
      hm.zsh
      hm.lazygit
      hm.askpass
      hm.nnn-niri
      hm.nnn-noctalia
      hm.lockscreen
    ];

    my.nh.subcommand = "os";
    my.nh.homeFlake = "/home/stiixxy/nixconf";
    my.git.userEmail = "veenman.stijn@gmail.com";
    my.git.sshSigningPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPQN61R7viARkAAIZF8JWmvXfs49/3l1BL4ozDMTadt2";
    my.nixconf.liveRepoPath = "/home/stiixxy/nixconf";

    home.username = "stiixxy";
    home.homeDirectory = "/home/stiixxy";

    programs.bash.enable = true;

    home.sessionVariables.NIX_PATH = "nixpkgs=${inputs.nixpkgs}";

    home.packages = with pkgs; [
      noctalia
      claude-code
      inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
      todoist-cli
      _1password-cli
      git-crypt
      hunk
      nixd
      alejandra
      nerd-fonts.jetbrains-mono
      inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default
      todoist-electron
      spotify
      discord
    ];

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*".IdentityFile = "~/.ssh/id_ed25519";
      extraConfig = ''
        Host *
            IdentityAgent ~/.1password/agent.sock
      '';
    };
  };
}
