{
  lib,
  pkgs,
  herdr,
  treehouse,
}: let
  bun = lib.getExe pkgs.bun;
  manifest = (pkgs.formats.toml {}).generate "herdr-plugin.toml" (import ./manifest.nix {inherit bun;});
  runtimeConfig = pkgs.writeText "treehouse-plugin-runtime.json" (builtins.toJSON {
    inherit bun;
    git = lib.getExe pkgs.git;
    gum = lib.getExe pkgs.gum;
    herdr = lib.getExe herdr;
    treehouse = lib.getExe treehouse;
  });
  activate = pkgs.writeTextFile {
    name = "treehouse-plugin-activate";
    executable = true;
    text = ''
      #!${bun}
      ${builtins.readFile ./activate.ts}
    '';
  };
in
  pkgs.runCommand "herdr-plugin-treehouse" {
    meta.mainProgram = "herdr-treehouse-activate";
  } ''
    plugin="$out/share/herdr/plugins/treehouse"
    mkdir -p "$out/bin" "$plugin"
    cp ${manifest} "$plugin/herdr-plugin.toml"
    cp ${runtimeConfig} "$plugin/runtime.json"
    cp ${./lib.ts} "$plugin/lib.ts"
    cp ${./new.ts} "$plugin/new.ts"
    cp ${./close.ts} "$plugin/close.ts"
    cp ${./confirm-force.ts} "$plugin/confirm-force.ts"
    cp ${activate} "$out/bin/herdr-treehouse-activate"

    ${bun} build "$plugin/new.ts" "$plugin/close.ts" "$plugin/confirm-force.ts" \
      --target bun --outdir "$TMPDIR/treehouse-plugin-check" >/dev/null
  ''
