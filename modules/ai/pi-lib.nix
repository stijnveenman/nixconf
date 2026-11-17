# Helpers for wiring Pi configuration and extensions, published as
# `flake.lib.pi` and consumed by `pi.nix` (and any other module that needs them).
{...}: {
  flake.lib.pi.mkHelpers = {
    config,
    lib,
    pkgs,
  }: let
    repoPath = config.my.nixconf.liveRepoPath;
    piAgent = ../../pi/agent;

    # A file under `pi/agent`: store copy, or a live symlink into the repo.
    source = path:
      if repoPath == null
      then piAgent + "/${path}"
      else config.lib.file.mkOutOfStoreSymlink "${repoPath}/pi/agent/${path}";

    # Links every entry of `pi/agent/<directory>` (minus `excluded`) plus `extra`.
    directory = directory: excluded: extra:
      pkgs.linkFarm "pi-${directory}" (
        map (name: {
          inherit name;
          path = source "${directory}/${name}";
        }) (lib.filter (name: !(builtins.elem name excluded))
          (builtins.attrNames (builtins.readDir (piAgent + "/${directory}"))))
        ++ extra
      );

    # Builds a Pi package from a non-flake input (`flake = false`), so a normal
    # `nix flake update` bumps it. Everything is derived from the source itself:
    #   - name/version from package.json
    #   - build step only when a `pi.extensions` entry is missing from the source
    #     (e.g. a `./dist` that is only produced when publishing)
    #   - npm (package-lock.json, no hash needed) or pnpm (pnpm-lock.yaml, needs
    #     `hash`; set it to `lib.fakeHash` and copy the printed hash)
    # Returns a linkFarm entry `{name, path}` for `~/.pi/agent/extensions`.
    package = {
      src,
      hash ? null,
    }: let
      manifest = lib.importJSON "${src}/package.json";
      # `@scope/name` -> `name`: extension directory names cannot contain a slash.
      name = lib.last (lib.splitString "/" manifest.name);
      version = "${manifest.version}-${src.shortRev or "dirty"}";
      needsBuild = lib.any (entry: !builtins.pathExists "${src}/${entry}") (manifest.pi.extensions or []);
      isPnpm = builtins.pathExists "${src}/pnpm-lock.yaml";

      npmPackage = pkgs.buildNpmPackage {
        pname = name;
        inherit version src;
        npmDeps = pkgs.importNpmLock {npmRoot = src;};
        inherit (pkgs.importNpmLock) npmConfigHook;
        dontNpmBuild = !needsBuild;
      };

      pnpmPackage = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = name;
        inherit version src;
        nativeBuildInputs = [pkgs.nodejs pkgs.pnpm pkgs.pnpmConfigHook];
        pnpmDeps = pkgs.fetchPnpmDeps {
          inherit (finalAttrs) pname version src;
          inherit hash;
          fetcherVersion = 5;
        };
        buildPhase = ''
          runHook preBuild
          ${lib.optionalString needsBuild "pnpm run build"}
          pnpm prune --prod
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/node_modules/${manifest.name}
          cp -r ./. $out/lib/node_modules/${manifest.name}
          runHook postInstall
        '';
      });
    in {
      inherit name;
      path = "${
        if isPnpm
        then pnpmPackage
        else npmPackage
      }/lib/node_modules/${manifest.name}";
    };
  in {
    inherit source directory package;
  };
}
