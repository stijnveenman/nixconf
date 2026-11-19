{
  config,
  inputs,
  ...
}: let
  hm = config.flake.modules.homeManager;
in {
  flake.modules.homeManager.macbook = {
    pkgs,
    config,
    ...
  }: {
    imports = [
      hm.git
      hm.nh
      hm.cli-tools
      hm.acli
      hm.tuicr
      hm.hunk
      hm.ghostty
      hm.opencode
      hm.pi
      hm.herdr
      hm.worktrunk
      hm.zsh
      hm.lazygit
      hm.gh-dash
    ];

    my.nh.subcommand = "home";
    my.nh.homeFlake = "/Users/${config.home.username}/Documents/nixconf";
    my.git.userEmail = "stijn.veenman@schiphol.nl";
    my.git.sshSigningPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIORX2ooYwWuacnHMvtFDoEGiNeJs1XllK/e+MZzrpkuf";
    my.nixconf.liveRepoPath = "${config.home.homeDirectory}/Documents/nixconf";
    my.worktrunk.worktreePath = "~/Documents/.wt-worktrees/{{ repo }}/{{ branch | sanitize_hash }}";

    nixpkgs.config.allowUnfree = true;

    home.username = "sv";
    home.homeDirectory = "/Users/sv";

    home.stateVersion = "24.05";

    home.sessionVariables = {
      # Pin nix-shell's <nixpkgs> to this flake's nixpkgs.
      NIX_PATH = "nixpkgs=${inputs.nixpkgs}";
      RUSH_PARALLELISM = "60%";
      PC_HIDE_DISABLED_PROC = "1";
    };

    # Local user bins (e.g. twg, used by the /handoff command) on PATH.
    home.sessionPath = ["$HOME/.local/bin"];

    home.packages = [
      pkgs._1password-cli
      inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs.todoist-cli
      pkgs.git-crypt

      # formatting
      pkgs.nixd
      pkgs.alejandra

      # fonts
      pkgs.nerd-fonts.jetbrains-mono
    ];

    programs.zsh.shellAliases = {
      ri = "rush install";
      rb = "rush build";
      rbt = "rush build --to";

      ac = "cd ~/Documents/airport-control/";
    };

    programs.home-manager.enable = true;

    # Treat the macOS Option key as Alt/Meta so terminal keybinds work.
    programs.ghostty.settings.macos-option-as-alt = true;
  };
}
