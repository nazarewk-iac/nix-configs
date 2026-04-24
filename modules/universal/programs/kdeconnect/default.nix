{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.kdeconnect;
in
{
  options.kdn.programs.kdeconnect = {
    enable = lib.mkEnableOption "kdeconnect setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.kdeconnect = lib.mkDefault cfg; } ];
    })
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.apps.kdeconnect = {
            enable = true;
            package.original = pkgs.kdePackages.kdeconnect-kde;
            dirs.cache = [ ];
            dirs.config = [ "kdeconnect" ];
            dirs.data = [ ];
            dirs.disposable = [ ];
            dirs.reproducible = [ ];
            dirs.state = [ ];
          };
        }
        (kdnConfig.util.ifTypes [ "darwin" ] {
          # TODO: probably install using this instead https://github.com/imshuhao/homebrew-kdeconnect
          kdn.apps.kdeconnect.package.install = false;
        })

        (kdnConfig.util.ifTypes [ "nixos" ] {
          # takes care of firewall
          programs.kdeconnect.enable = true;
        })
        (lib.attrsets.optionalAttrs
          (kdnConfig.util.hasParentOfAnyType [ "nixos" ] && kdnConfig.util.isOfType [ "home-manager" ])
          {
            services.kdeconnect.enable = true;
            services.kdeconnect.indicator = true;
            services.kdeconnect.package = config.kdn.apps.kdeconnect.package.final;
          }
        )
      ]
    ))
  ];
}
