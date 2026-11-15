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

    # Keep boot and shutdown silent: no kernel/initrd logs, no systemd status
    # lines, no blinking console cursor before the splash or greeter appears.
    # 0 also hides the kernel's highest-priority messages, such as the
    # firmware warning "RDSEED32 is broken" on this CPU; they stay in the journal.
    boot.consoleLogLevel = 0;
    boot.kernelParams = [
      "quiet"
      "splash"
      "rd.udev.log_level=3"
      "udev.log_level=3"
      "rd.systemd.show_status=false"
      "systemd.show_status=false"
      "vt.global_cursor_default=0"
    ];

    # logind writes "The system will reboot now!" to every logged-in terminal on
    # reboot/poweroff, which flashes on the console as the session closes.
    # `systemctl reboot` turns this back on per call unless given --no-wall
    # (see the noctalia session actions).
    services.logind.settings.Login.WallMessages = false;

    # systemd arms the hardware watchdog for the final reboot step; the kernel
    # then prints "watchdog did not stop!" over the splash. Without it a hung
    # shutdown is not force-rebooted after 10 minutes.
    systemd.settings.Manager.RebootWatchdogSec = "off";
  };
}
