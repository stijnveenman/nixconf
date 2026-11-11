{pkgs, ...}: let
  version = "1.3.40-stable";
  sources = {
    aarch64-darwin = {
      platform = "darwin_arm64";
      hash = "sha256-cFZhhtLh0BFg7w3DWu/B/7RtHdSmD/QaRSSK34uJe5c=";
    };
    x86_64-darwin = {
      platform = "darwin_amd64";
      hash = "sha256-kvroed4kPzwS/IBdTxVPmjMQkel0U2xANbrmlvlnMP8=";
    };
    x86_64-linux = {
      platform = "linux_amd64";
      hash = "sha256-GcETeJ6KZr8RqA3BjPdefnuiOREgBfTpzWnbBfEaxSY=";
    };
    aarch64-linux = {
      platform = "linux_arm64";
      hash = "sha256-sYgPZvKZqytWUoyQu/9QyoJj5zMYaKMdC2yntn90aeU=";
    };
  };
  src = sources.${pkgs.stdenv.hostPlatform.system};
  acli = pkgs.stdenvNoCC.mkDerivation {
    pname = "acli";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://acli.atlassian.com/${pkgs.lib.head (pkgs.lib.splitString "_" src.platform)}/${version}/acli_${version}_${src.platform}.tar.gz";
      inherit (src) hash;
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.autoPatchelfHook];
    installPhase = ''
      install -Dm755 */acli $out/bin/acli
    '';
    meta.mainProgram = "acli";
  };
in {
  home.packages = [acli];
}
