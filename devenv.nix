{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  extraDevenvFiles = lib.pipe (builtins.readDir ./.) [
    builtins.attrNames
    (builtins.filter (
      name:
      name != "devenv.nix"
      && name != "devenv.local.nix"
      && lib.hasPrefix "devenv." name
      && lib.hasSuffix ".nix" name
    ))
    (map (name: ./. + "/${name}"))
  ];
in
{
  imports = [
    (inputs.nix-configs.mkSlots {
      inherit pkgs;
      imports = extraDevenvFiles;

      kdn.isSourceRepo = true;

      kdn.nix.enable = true;
      kdn.jj.enable = true;

      kdn.mcp = {
        enable = true;
        basic-memory.enable = true;
      };
    }).config.devenv
  ];

  overlays = [ inputs.nix-configs.overlays.packages ];
}
