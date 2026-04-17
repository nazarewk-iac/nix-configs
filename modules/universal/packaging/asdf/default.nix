{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.packaging.asdf;
in {
  options.kdn.packaging.asdf = {
    enable = lib.mkEnableOption "ASDF version manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.asdf-vm;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          cfg.package
          unzip
          coreutils
        ];
      }
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [{kdn.packaging.asdf.enable = true;}];
      })
      (kdnConfig.util.ifHM {
        programs.fish.interactiveShellInit = ''
          fish_add_path --prepend --move "$HOME/.asdf/shims"
        '';
        home.activation = {
          asdfReshim = lib.hm.dag.entryAfter ["writeBoundary"] ''
            if [ -d "$HOME/.asdf/shims" ] ; then
              $DRY_RUN_CMD rm -rf "$HOME/.asdf/shims"
            fi
            $DRY_RUN_CMD "${cfg.package}/bin/asdf" reshim
          '';
        };
      })
      (kdnConfig.util.ifTypes ["nixos"] {
        environment.interactiveShellInit = ''
          [[ -z "$HOME" ]] || export PATH="$HOME/.asdf/shims:$PATH"
        '';
      })
    ]
  );
}
