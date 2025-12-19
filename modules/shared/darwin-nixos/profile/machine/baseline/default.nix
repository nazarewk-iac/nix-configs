{
  lib,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.openssh.enable = true;
      environment.etc."kdn/source-flake".source = kdnConfig.self;
      nix.gc.automatic = true;
      # angrr seems to drop all of the sources regularly, maybe I could integrate `angrr touch` to prevent this?
      services.angrr.enable = true;
      # using example from https://github.com/linyinfeng/angrr/blob/35f13906a4a6410f92eefa9678526ac81321e816/README.md#nixos-module-usage
      services.angrr.settings = {
        temporary-root-policies = {
          direnv = {
            path-regex = "/\\.direnv/";
            period = "7d";
          };
          result = {
            path-regex = "/result[^/]*$";
            period = "3d";
          };
        };
        profile-policies = {
          system = {
            profile-paths = ["/nix/var/nix/profiles/system"];
            keep-since = "14d";
            keep-latest-n = 5;
            keep-booted-system = true;
            keep-current-system = true;
          };
          user = {
            enable = false; # Policies can be individually disabled
            profile-paths = [
              # `~` at the beginning will be expanded to the home directory of each discovered user
              "~/.local/state/nix/profiles/profile"
              "/nix/var/nix/profiles/per-user/root/profile"
            ];
            keep-since = "1d";
            keep-latest-n = 1;
          };
          # You can define your own policies
          # ...
        };
      };
    }
    (kdnConfig.util.ifTypes ["nixos"] {
      services.angrr.enableNixGcIntegration = true;
    })
  ]);
}
