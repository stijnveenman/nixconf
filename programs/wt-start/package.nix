{
  lib,
  rustPlatform,
  makeBinaryWrapper,
  git,
  gh,
  worktrunk,
  herdr,
  pi,
}:
rustPlatform.buildRustPackage {
  pname = "wt-start";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./generate-branch-name.md
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [makeBinaryWrapper];

  postInstall = ''
    wrapProgram $out/bin/wt-start \
      --prefix PATH : ${lib.makeBinPath [git gh worktrunk herdr pi]}
  '';

  meta.mainProgram = "wt-start";
}
