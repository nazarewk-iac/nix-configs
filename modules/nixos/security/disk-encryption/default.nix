{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.security.disk-encryption;
in {
  options.kdn.security.disk-encryption = {
    enable = lib.mkEnableOption "disk encryption wrapper setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.toolset.fs.encryption.enable = true;
        security.tpm2.enable = true;
      }
    ]
  );
}
