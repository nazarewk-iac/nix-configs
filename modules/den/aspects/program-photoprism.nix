# `kdn.programs.photoprism`, as a den aspect.
# It ports `modules/universal/programs/photoprism/default.nix`.
#
# NixOS only. The old module wraps its whole body in `ifTypes [ "nixos" ]`, so no other class gets a
# target here.
#
# `originalsDevice` keeps its `nullOr` type and its `null` default. A `lib.mkOptionDefault` cannot
# neutralise that default, because the option's own default sits at priority 1500. A consumer that
# must un-set it uses `lib.mkOverride 1400`.
{ ... }:
{
  kdn.program-photoprism.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.programs.photoprism;
    in
    {
      options.kdn.programs.photoprism.originalsDevice = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/srv/photos";
        description = ''
          Directory that the aspect bind-mounts onto the photoprism originals path.

          `null` mounts nothing, and photoprism then reads whatever the originals path already
          holds.

          A `lib.mkOptionDefault` cannot neutralise this default, because the type is `nullOr`.
          Use `lib.mkOverride 1400` when a consumer must un-set it.
        '';
      };

      config = {
        services.photoprism.enable = true;
        services.photoprism.passwordFile = "/tmp/photoprism-admin";
        services.photoprism.originalsPath = "/var/lib/private/photoprism/originals";
        services.photoprism.settings.PHOTOPRISM_READONLY = "true";
        services.photoprism.settings.PHOTOPRISM_ORIGINALS_LIMIT = "2000";

        # `fsType = "none"` is the mount(8) spelling for a bind mount. The old module leaves it out.
        # Current nixpkgs dropped the `default = "auto"` from `fileSystems.<name>.fsType`, so the
        # old module cannot evaluate any more when `originalsDevice` holds a value. Measured
        # 2026-09-11 with `nixos/modules/tasks/filesystems.nix:124`. No host enables the old module,
        # so the defect stayed latent. This aspect names the type.
        fileSystems = lib.mkIf (cfg.originalsDevice != null) {
          "/var/lib/private/photoprism/originals" = {
            device = cfg.originalsDevice;
            fsType = "none";
            options = [ "bind" ];
          };
        };
      };
    };
}
