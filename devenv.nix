{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-configs.devenvModules.default ];

  overlays = [ inputs.nix-configs.overlays.packages ];

  kdn.isSourceRepo = true;

  kdn.nix.enable = true;
  kdn.jj.enable = true;

  kdn.mcp = {
    enable = true;
    basic-memory.enable = true;
  };
}
