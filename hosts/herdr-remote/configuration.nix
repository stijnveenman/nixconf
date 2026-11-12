{
  modulesPath,
  pkgs,
  ...
}: let
  # Public key already used by the macOS host. This is for installation and
  # recovery SSH access, not the separate Git key created on this machine.
  bootstrapKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIORX2ooYwWuacnHMvtFDoEGiNeJs1XllK/e+MZzrpkuf";
in {
  imports = [(modulesPath + "/profiles/qemu-guest.nix")];

  system.stateVersion = "26.05";
  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    substituters = ["https://nix-community.cachix.org"];
    trusted-public-keys = ["nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="];
  };

  networking.hostName = "herdr-remote";
  networking.useDHCP = true;
  time.timeZone = "Europe/Amsterdam";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  services.qemuGuest.enable = true;
  services.tailscale.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  programs.zsh.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/herdr-remote/nixconf";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep=10";
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [bootstrapKey];
  users.users.herdr-remote = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "Herdr Remote";
    openssh.authorizedKeys.keys = [bootstrapKey];
  };

  environment.systemPackages = [pkgs.git];
}
