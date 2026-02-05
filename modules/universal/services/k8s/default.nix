{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.services.k8s;
in {
  options.kdn.services.k8s = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = builtins.any (clusterCfg: clusterCfg.isMember) (builtins.attrValues kdnConfig.k8s.clusters);
    };
    management.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    packages.default = lib.mkPackageOption pkgs "kubernetes" {};
    packages.cilium-cli = lib.mkPackageOption pkgs "cilium-cli" {};
    packages.containerd = lib.mkPackageOption pkgs "containerd" {};
    packages.cri-tools = lib.mkPackageOption pkgs "cri-tools" {};
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable || cfg.management.enable) {
      assertions = [
        {
          assertion = lib.pipe kdnConfig.k8s.clusters [
            builtins.attrValues
            (builtins.filter (clusterCfg: clusterCfg.enable))
            (map (clusterCfg: builtins.any (allowed: lib.hasPrefix allowed cfg.packages.default.version) clusterCfg.allowedVersions))
            (builtins.all lib.id)
          ];
          message = ''Kubernetes cluster is pinned to unsupported version!'';
        }
      ];
    })
    (lib.mkIf cfg.management.enable {
      kdn.env.packages = [
        cfg.packages.default
        cfg.packages.cilium-cli
      ];
    })
  ];
}
