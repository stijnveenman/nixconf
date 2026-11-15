{config, ...}: {
  flake.modules.nixos.nnn = {pkgs, ...}: {
    imports = [config.flake.modules.nixos.nnn-hardware];

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "26.05";
    nix.settings.experimental-features = ["nix-command" "flakes"];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    # Skip the boot menu; hold Space at power-on to show it.
    boot.loader.timeout = 0;

    networking.hostName = "nnn";
    networking.networkmanager.enable = true;

    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "client";
    };

    time.timeZone = "Europe/Amsterdam";
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "nl_NL.UTF-8";
      LC_IDENTIFICATION = "nl_NL.UTF-8";
      LC_MEASUREMENT = "nl_NL.UTF-8";
      LC_MONETARY = "nl_NL.UTF-8";
      LC_NAME = "nl_NL.UTF-8";
      LC_NUMERIC = "nl_NL.UTF-8";
      LC_PAPER = "nl_NL.UTF-8";
      LC_TELEPHONE = "nl_NL.UTF-8";
      LC_TIME = "nl_NL.UTF-8";
    };

    services.xserver.enable = true;
    services.desktopManager.gnome.enable = false;
    programs.zsh.enable = true;
    users.defaultUserShell = pkgs.zsh;

    programs.niri = {
      enable = true;
      package = pkgs.niri;
    };

    environment.systemPackages = with pkgs; [
      xwayland-satellite
      gnomeExtensions.auto-power-profile
    ];

    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };

    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    powerManagement = {
      enable = true;
      cpuFreqGovernor = "ondemand";
    };
    # services.power-profiles-daemon.enable = false;
    services.upower.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    users.users."stiixxy" = {
      isNormalUser = true;
      description = "stiixxy";
      extraGroups = ["networkmanager" "wheel"];
      packages = with pkgs; [
        google-chrome
        _1password-gui
        _1password-cli
        kdePackages.dolphin
      ];
    };

    programs.nix-ld.enable = true;
    fonts.packages = [pkgs.nerd-fonts.jetbrains-mono];
  };
}
