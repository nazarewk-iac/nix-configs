{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-configs.devenvModules.default ];

  kdn.nix.enable = true;

  kdn.mcp = {
    enable = true;
    programs = {
      git.enable = true;
    };
  };
}
