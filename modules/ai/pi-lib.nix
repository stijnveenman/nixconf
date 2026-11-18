# Home Manager helpers share the consuming host's config and package set.
{config, ...}: let
  flakeModules = config.flake.modules;
in {
  flake.modules.homeManager.pi-lib = {
    config,
    lib,
    pkgs,
    ...
  }: let
    piAgent = ../../pi/agent;

    # A file under `pi/agent`: store copy, or a live symlink into the repo.
    source = path: config.lib.nixconf.source "pi/agent/${path}";

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
      # Package directory inside a monorepo `src` (pnpm workspace).
      subdir ? null,
      # For sources whose lockfile cannot be used (e.g. no `resolved` URLs):
      # `{name = path;}` dependencies linked into `node_modules`, no install step.
      nodeModules ? null,
    }: let
      pkgDir =
        if subdir == null
        then "${src}"
        else "${src}/${subdir}";
      manifest = lib.importJSON "${pkgDir}/package.json";
      # `@scope/name` -> `name`: extension directory names cannot contain a slash.
      name = lib.last (lib.splitString "/" manifest.name);
      version = "${manifest.version}-${src.shortRev or "dirty"}";
      needsBuild = lib.any (entry: !builtins.pathExists "${pkgDir}/${entry}") (manifest.pi.extensions or []);
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
          pnpmWorkspaces = lib.optional (subdir != null) manifest.name;
        };
        pnpmWorkspaces = lib.optional (subdir != null) manifest.name;
        buildPhase = ''
          runHook preBuild
          ${lib.optionalString needsBuild (
            if subdir == null
            then "pnpm run build"
            else "pnpm --filter ${manifest.name} run build"
          )}
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

      linkedPackage = pkgs.runCommand "${name}-${version}" {} ''
        dest=$out/lib/node_modules/${manifest.name}
        mkdir -p $dest
        cp -r ${src}/. $dest
        chmod -R u+w $dest
        mkdir -p $dest/node_modules
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (dep: depPath: ''
            mkdir -p $dest/node_modules/$(dirname ${dep})
            cp -r ${depPath} $dest/node_modules/${dep}
          '')
          (lib.optionalAttrs (nodeModules != null) nodeModules))}
      '';
    in {
      inherit name;
      path = "${
        if nodeModules != null
        then linkedPackage
        else if isPnpm
        then pnpmPackage
        else npmPackage
      }/lib/node_modules/${manifest.name}${lib.optionalString (subdir != null) "/${subdir}"}";
    };
  in {
    imports = [flakeModules.homeManager.repo];
    config.lib.pi = {inherit source directory package;};
  };
}
