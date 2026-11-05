{lib}: {
  pluginEntry = root: let
    manifest = lib.importTOML "${root}/herdr-plugin.toml";
  in {
    plugin_id = manifest.id;
    inherit (manifest) name version;
    min_herdr_version = manifest.min_herdr_version;
    manifest_path = "${root}/herdr-plugin.toml";
    plugin_root = toString root;
    enabled = true;
    source.kind = "local";
  };

  action = key: command: description: {
    inherit key command description;
    type = "plugin_action";
  };
}
