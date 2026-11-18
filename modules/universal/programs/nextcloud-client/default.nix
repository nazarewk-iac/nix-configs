{
  lib,
  pkgs,
  config,
  kdnConfig,
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
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.programs.nextcloud-client = lib.mkDefault cfg; } ];
      })
      (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
        lib.mkMerge [
          {
            /*
              TODO: try an automated login on activation using `sops-nix` credentials?
               - make sure at least password-store & Keepass are downloaded (and not much more)
            */
            services.nextcloud-client.enable = true;
            services.nextcloud-client.package = config.kdn.apps.nextcloud-client.package.final;
            services.nextcloud-client.startInBackground = true;
            # Wait for the Secret Service unlock before the client reads its credentials;
            # otherwise it races rosec and shows the browser login.
            systemd.user.services.nextcloud-client = {
              Unit.Wants = [ "rosec-unlock.service" ];
              Unit.After = [ "rosec-unlock.service" ];
              Service.Restart = "on-failure";
            };
            kdn.apps.nextcloud-client = {
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
      ))
    ]
  );
}
