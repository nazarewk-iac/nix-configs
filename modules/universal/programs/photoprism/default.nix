{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.photoprism;
in
{
  options.kdn.programs.photoprism = {
    enable = lib.mkEnableOption "photoprism photo management service";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      # see https://nixos.wiki/wiki/PhotoPrism
      # see https://github.com/NixOS/nixpkgs/blob/fcc147b1e9358a8386b2c4368bd928e1f63a7df2/nixos/modules/services/web-apps/photoprism.nix
      services.photoprism.enable = true;
      services.photoprism.passwordFile = "/tmp/photoprism-admin";
      services.photoprism.originalsPath = "/var/lib/private/photoprism/originals";
      services.photoprism.settings.PHOTOPRISM_READONLY = "true";
      services.photoprism.settings.PHOTOPRISM_ORIGINALS_LIMIT = "2000";

      fileSystems."/var/lib/private/photoprism/originals" = {
        device = "${config.kdn.profile.user.kdn.homeDir}/Nextcloud/drag0nius@nc.nazarewk.pw";
        options = [ "bind" ];
      };
    }
  );
}
