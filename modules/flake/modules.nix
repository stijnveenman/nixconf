# `flake.modules.<class>.<name>`: the registry of NixOS / home-manager modules
# that every file in this tree publishes into and every host consumes.
#
# This replaces flake-parts' `flakeModules.modules`, which wraps each module in
# three extra layers of `imports`. Import depth decides the order in which list
# definitions (home.packages, environment.systemPackages, ...) are merged, so
# that wrapping reorders them and changes the built store paths. Here a module
# defined in one file is used exactly as written (with `_file`/`_class` added);
# a module defined in several files becomes `{ imports = [ ... ]; }`.
{lib, ...}: let
  annotate = class: file: module:
    if lib.isFunction module
    then lib.setFunctionArgs (args: annotate class file (module args)) (lib.functionArgs module)
    else if lib.isAttrs module
    then {_file = file;} // lib.optionalAttrs (class != "generic") {_class = class;} // module
    else module;

  moduleType = lib.mkOptionType {
    name = "module";
    description = "module";
    check = m: lib.isAttrs m || lib.isFunction m || lib.isPath m;
    merge = loc: defs: let
      class = lib.elemAt loc 2;
      annotated = map (def: annotate class def.file def.value) defs;
    in
      if lib.length annotated == 1
      then lib.head annotated
      else {imports = annotated;};
  };
in {
  options.flake.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf moduleType);
    default = {};
    description = "Modules published by this flake, grouped by module class.";
  };
}
