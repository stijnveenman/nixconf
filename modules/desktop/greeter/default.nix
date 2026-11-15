{
  # Login screen: SDDM with a custom theme styled like the plymouth splash,
  # NixOS logo with only a password prompt below it (no user/session picker).
  flake.modules.nixos.greeter = {pkgs, ...}: let
    themeName = "nixos-login";

    theme = pkgs.runCommand "sddm-theme-${themeName}" {} ''
      dir=$out/share/sddm/themes/${themeName}
      mkdir -p $dir
      cp ${./theme/Main.qml} $dir/Main.qml
      cp ${./theme/metadata.desktop} $dir/metadata.desktop
      cp ${pkgs.nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake.png $dir/logo.png
      cat > $dir/theme.conf <<CONF
      [General]
      user=stiixxy
      font=JetBrainsMono Nerd Font
      CONF
    '';
  in {
    services.displayManager = {
      defaultSession = "niri";
      sddm = {
        enable = true;
        wayland.enable = true;
        theme = themeName;
      };
    };

    environment.systemPackages = [theme];
  };
}
