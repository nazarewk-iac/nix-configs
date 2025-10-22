{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.security.secrets;
in {
  options.kdn.security.secrets = {
    enable = lib.mkEnableOption "Nix secrets setup";
    allow = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    allowed = lib.mkOption {
      readOnly = true;
      type = with lib.types; bool;
      default = cfg.allow && cfg.enable;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.allow || (config.sops.secrets == {} && config.sops.templates == {});
            message = "`sops.secrets` and `sops.templates` must be empty when `kdn.security.secrets.allow` is `false`";
          }
        ];
      }
      {
        systemd.targets.kdn-secrets = {
          description = "kdn's secrets loaded for the first time";
          upholds = ["kdn-secrets-reload.target"];
        };
        systemd.targets.kdn-secrets-reload = {
          description = "kdn's secrets reload target";
          after = ["kdn-secrets.target"];
          requires = ["kdn-secrets.target"];
          wantedBy = ["kdn-secrets.target"];
          partOf = ["kdn-secrets.target"];
        };
      }
    ]
  );
}
