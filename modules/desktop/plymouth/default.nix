{
  # Graphical boot splash: NixOS logo with a progress bar instead of boot logs.
  flake.modules.nixos.plymouth = {pkgs, ...}: let
    theme = "nixos-bar";
    magick = "${pkgs.imagemagick}/bin/magick";

    themePackage = pkgs.runCommand "plymouth-theme-${theme}" {} ''
      dir=$out/share/plymouth/themes/${theme}
      mkdir -p $dir
      cp ${./theme/nixos-bar.script} $dir/${theme}.script
      cp ${pkgs.nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake.png $dir/logo.png
      ${magick} -size 1x1 xc:'#2a2d36' $dir/track.png
      ${magick} -size 1x1 xc:'#7ebae4' $dir/fill.png
      cat > $dir/${theme}.plymouth <<PLY
      [Plymouth Theme]
      Name=NixOS Bar
      Description=NixOS logo with a boot progress bar
      ModuleName=script

      [script]
      ImageDir=$dir
      ScriptFile=$dir/${theme}.script
      PLY
    '';
  in {
    boot.plymouth = {
      enable = true;
      inherit theme;
      themePackages = [themePackage];
    };

    # Hide kernel and initrd logs behind the splash.
    boot.consoleLogLevel = 3;
    boot.kernelParams = [
      "quiet"
      "splash"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
  };
}
