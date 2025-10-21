{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.nextcloud-client;
in
{
  options.kdn.programs.nextcloud-client = {
    enable = lib.mkEnableOption "nextcloud-client-desktop setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        /*
          TODO: try an automated login on activation using `sops-nix` credentials?
           - make sure at least password-store & Keepass are downloaded (and not much more)
        */
        services.nextcloud-client.enable = true;
        services.nextcloud-client.package = config.kdn.programs.apps.nextcloud-client.package.final;
        services.nextcloud-client.startInBackground = true;
        systemd.user.services.nextcloud-client.Service = {
          Restart = "on-failure";
        };
        kdn.programs.apps.nextcloud-client = {
          enable = true;
          package.install = false;
          dirs.cache = [ "Nextcloud" ];
          dirs.config = [ "Nextcloud" ];
          dirs.data = [ "Nextcloud" ];
          dirs.disposable = [ ];
          dirs.reproducible = [ "/Nextcloud" ];
          dirs.state = [ ];
        };
      }
    ]
  );
}
