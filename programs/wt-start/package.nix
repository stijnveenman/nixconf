{
  lib,
  rustPlatform,
  makeBinaryWrapper,
  git,
  gh,
  worktrunk,
  herdr,
}:
rustPlatform.buildRustPackage {
  pname = "wt-start";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [makeBinaryWrapper];

  postInstall = ''
    wrapProgram $out/bin/wt-start \
      --prefix PATH : ${lib.makeBinPath [git gh worktrunk herdr]}
  '';

  meta.mainProgram = "wt-start";
}
