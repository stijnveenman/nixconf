{
  pkgs,
  config,
  lib,
  pi,
  inputs,
  ...
}: {
  imports = [
    ../../modules/git.nix
    ../../modules/cli-tools.nix
    ../../modules/acli.nix
    ../../modules/tuicr.nix
    ../../modules/ghostty.nix
    ../../modules/opencode.nix
    ../../modules/pi.nix
    ../../modules/raycast
    ../../modules/herdr
    ../../modules/zsh.nix
    ../../modules/lazygit.nix
  ];

  my.git.userEmail = "stijn.veenman@schiphol.nl";
  my.nixconf.liveRepoPath = "${config.home.homeDirectory}/Documents/nixconf";
  my.herdr.worktreePath = "~/Documents/.wt-worktrees/{{ repo }}/{{ branch | sanitize_hash }}";

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
    ${config.my.git.userEmail} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIORX2ooYwWuacnHMvtFDoEGiNeJs1XllK/e+MZzrpkuf
  '';

  nixpkgs.config.allowUnfree = true;

  home.username = "sv";
  home.homeDirectory = "/Users/sv";

  home.stateVersion = "24.05";

  programs.nh = {
    enable = true;
    homeFlake = "/Users/${config.home.username}/Documents/nixconf";

    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep=10";
    };
  };

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
    pi.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.todoist-cli
    pkgs.git-crypt
    pkgs.hunk

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

  programs.ghostty = {
    # Host-specific ghostty settings (shared theme/font/package live in
    # ../../modules/ghostty.nix). These are macbook-only: macOS Option-as-Alt.
    settings = {
      # Treat the macOS Option key as Alt/Meta so terminal keybinds work.
      macos-option-as-alt = true;

      # Fully quit Ghostty when the last window closes so reopening starts a
      # fresh process.
      quit-after-last-window-closed = true;
    };
  };
}
