{
  pkgs,
  lib,
  ...
}: let
  scrcpy = lib.getExe pkgs.scrcpy;
  haydayScript = pkgs.writeShellScript "raycast-hayday" ''
    # Required parameters:
    # @raycast.schemaVersion 1
    # @raycast.title Launch Hay Day
    # @raycast.mode silent
    # @raycast.packageName scrcpy

    export PATH="${lib.makeBinPath [pkgs.scrcpy pkgs.android-tools]}:$PATH"
    exec ${scrcpy} \
      --tcpip=192.168.1.145:5555 \
      --video-codec=h264 \
      --new-display \
      --start-app=+com.supercell.hayday \
      --always-on-top
  '';
in {
  home.packages = [
    pkgs.android-tools
    pkgs.scrcpy
  ];

  home.file.".raycast/scripts/hayday.sh".source = haydayScript;
}
