# `kdn.programs.nextcloud-client`, as a den aspect.
# It ports `modules/universal/programs/nextcloud-client/default.nix`.
{ kdn, ... }:
{
  kdn.program-nextcloud-client.includes = [ kdn.apps ];

  kdn.program-nextcloud-client.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        services.nextcloud-client.enable = true;
        services.nextcloud-client.package = config.kdn.apps.nextcloud-client.package.final;
        services.nextcloud-client.startInBackground = true;
        systemd.user.services.nextcloud-client.Service.Restart = "on-failure";

        kdn.apps.nextcloud-client = {
          enable = true;
          package.install = false;
          dirs.cache = [ "Nextcloud" ];
          dirs.config = [ "Nextcloud" ];
          dirs.data = [ "Nextcloud" ];
          # The leading `/` makes the path relative to the home directory. It names the sync target,
          # not a state directory.
          dirs.reproducible = [ "/Nextcloud" ];
        };
      };
    };
}
