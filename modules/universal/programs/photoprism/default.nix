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

    originalsDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/srv/photos";
      description = ''
        Directory that the module bind-mounts onto the photoprism originals path.

        `null` means the module mounts nothing, and photoprism then reads whatever the
        originals path already holds. `data/programs-photoprism.nix` supplies the owner's
        directory.

        A `lib.mkOptionDefault` cannot neutralise this default, because the type is `nullOr`.
        Use `lib.mkOverride 1400` when a consumer must un-set it.
      '';
    };
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

      fileSystems = lib.mkIf (cfg.originalsDevice != null) {
        "/var/lib/private/photoprism/originals" = {
          device = cfg.originalsDevice;
          options = [ "bind" ];
        };
      };
    }
  );
}
