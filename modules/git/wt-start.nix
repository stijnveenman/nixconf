# `wt start`: the Rust program in programs/wt-start, exposed as `packages.<system>.wt-start`.
{
  perSystem = {
    inputs',
    lib,
    pkgs,
    ...
  }: {
    packages.wt-start = pkgs.rustPlatform.buildRustPackage {
      pname = "wt-start";
      version = "0.1.0";
      src = lib.fileset.toSource {
        root = ../../programs/wt-start;
        fileset = lib.fileset.unions (map (path: ../../programs/wt-start + "/${path}") [
          "Cargo.toml"
          "Cargo.lock"
          "generate-branch-name.md"
          "src"
        ]);
      };
      cargoLock.lockFile = ../../programs/wt-start/Cargo.lock;
      nativeBuildInputs = [pkgs.makeBinaryWrapper];

      postInstall = ''
        wrapProgram $out/bin/wt-start \
          --prefix PATH : ${lib.makeBinPath [
          pkgs.git
          pkgs.git-crypt
          pkgs.gh
          pkgs.worktrunk
          inputs'.herdr.packages.default
          inputs'.pi.packages.default
        ]}
      '';

      meta.mainProgram = "wt-start";
    };
  };
}
