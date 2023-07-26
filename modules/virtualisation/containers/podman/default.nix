{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.virtualisation.containers.podman;
in
{
  options.kdn.virtualisation.containers.podman = {
    enable = lib.mkEnableOption "Podman setup";

    rootless.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      virtualisation.docker.enable = lib.mkDefault false;
      virtualisation.podman.enable = true;

      virtualisation.oci-containers.backend = "podman";
      virtualisation.podman.dockerCompat = !config.virtualisation.docker.enable;
      virtualisation.podman.dockerSocket.enable = !config.virtualisation.docker.enable;
      environment.systemPackages = with pkgs; [
        # podman # conflicts with option's wrapper
        buildah
      ];
    }
    (lib.mkIf cfg.rootless.enable {
      home-manager.sharedModules = [{
        kdn = {
          virtualisation.containers.enable = true;
          virtualisation.containers.storage.settings = {
            ## it is working this way by default for rootless
            storage.driver = "overlay";
            ## this is already used
            storage.options.overlay.mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs";
          };
        };
      }];
      boot.kernel.sysctl."user.max_user_namespaces" = 15000;
    })
    (lib.mkIf (!cfg.rootless.enable) {
      home-manager.sharedModules = [{
        home.packages = [
          (pkgs.writeShellApplication {
            name = "podman";
            runtimeInputs = with pkgs; [ podman ];
            text = ''
              if [[ "$EUID" != 0 ]]; then
                exec sudo --preserve-env podman "$@"
              fi
              exec podman "$@"
            '';
          })
        ];
      }];
    })
  ]);
}
