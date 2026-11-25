{
  # Steam with Proton-GE, GameMode and gamescope.
  flake.modules.nixos.steam = {pkgs, ...}: {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      protontricks.enable = true;
      extraCompatPackages = [pkgs.proton-ge-bin];
    };
    # 32-bit Vulkan/GL for Proton; programs.steam enables this too, set explicitly for clarity.
    hardware.graphics.enable32Bit = true;
    # Launch option: `gamemoderun %command%` (CPU governor + scheduling boost).
    programs.gamemode.enable = true;
    # Launch option: `gamescope -f -- %command%` for fixed-res/upscaled games under niri.
    programs.gamescope.enable = true;
    users.users.stiixxy.extraGroups = ["gamemode"];
  };
}
