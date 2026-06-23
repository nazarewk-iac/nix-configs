{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-configs.devenvModules.default ];

  overlays = [ inputs.nix-configs.overlays.packages ];

  kdn.nix.enable = true;

  kdn.mcp = {
    enable = true;
    programs = {
      git.enable = true;
      nixos.enable = true;
      filesystem = {
        enable = true;
        args = [ "/nix/store" ];
      };
      sequential-thinking.enable = true;
      time.enable = true;
      fetch.enable = true;
    };
    extraBackends = {
      devenv = {
        command = "devenv mcp";
        description = "devenv — search nixpkgs packages and devenv options";
        env.DEVENV_ROOT = toString ./.;
      };
      jj = {
        command = "${pkgs.kdn.jj-mcp}/bin/jj-mcp";
        description = "jj — Jujutsu version control tools";
      };
    };
  };
}
