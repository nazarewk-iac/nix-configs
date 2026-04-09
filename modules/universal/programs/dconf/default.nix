{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.programs.dconf = {
            enable = lib.mkOption {
              default = false;
            };
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.programs.dconf;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
            lib.mkMerge [
              {
                dconf.enable = true;
                kdn.apps.dconf = {
                  enable = true;
                  package.install = false;
                  dirs.cache = [];
                  dirs.config = ["dconf"];
                  dirs.data = [];
                  dirs.disposable = [];
                  dirs.reproducible = [];
                  dirs.state = [];
                };
              }
            ]
          )));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.programs.dconf;
        in {

          config = lib.mkIf cfg.enable (
              lib.mkMerge [
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.dconf = lib.mkDefault cfg;}];})
{
                programs.dconf.enable = true;
                home-manager.sharedModules = [{kdn.programs.dconf.enable = true;}];
              }
            ]
          );
        }
      )
    )
  ];
}
