{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.security.disk-encryption;
in
{
  options.kdn.security.disk-encryption = {
    enable = lib.mkEnableOption "disk encryption wrapper setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.toolset.fs.encryption.enable = true;
          security.tpm2.enable = true;
        }
      ]
    )
  );
}
