{
  lib,
  config,
  pkgs,
  ...
}: {
  options.k8s.clusters = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...} @ clusterArgs: let
      clusterCfg = clusterArgs.config;
    in {
      options.enable = lib.mkEnableOption "cluster configuration";
      options.name = lib.mkOption {
        type = lib.types.str;
        default = name;
      };
      options.domain = lib.mkOption {
        type = lib.types.str;
      };
      options.allowedVersions = lib.mkOption {
        type = with lib.types; listOf str;
      };
      options.apiserver.vrrp.masterNode = lib.mkOption {
        type = lib.types.str;
      };
      options.apiserver.vrrp.id = lib.mkOption {
        type = lib.types.ints.u8;
      };
      options.apiserver.vrrp.ipv4 = lib.mkOption {
        type = lib.types.str;
      };
      options.apiserver.vrrp.ipv6 = lib.mkOption {
        type = lib.types.str;
      };
      options.apiserver.port.internal = lib.mkOption {
        type = lib.types.ints.u16;
      };
      options.apiserver.port.shared = lib.mkOption {
        type = lib.types.ints.u16;
      };
      options.apiserver.interface = lib.mkOption {
        type = lib.types.str;
      };
      options.apiserver.domain = lib.mkOption {
        type = lib.types.str;
      };
      options.subnet.pod = lib.mkOption {
        type = with lib.types; listOf str;
      };
      options.subnet.service = lib.mkOption {
        type = with lib.types; listOf str;
      };
      options.controlplane.nodes = lib.mkOption {
        type = with lib.types; listOf str;
      };
      options.controlplane.enabled = lib.mkOption {
        readOnly = true;
        default = builtins.any (node: node == config.hostName) clusterCfg.controlplane.nodes;
      };
      options.worker.nodes = lib.mkOption {
        type = with lib.types; listOf str;
      };
      options.worker.enabled = lib.mkOption {
        readOnly = true;
        default = builtins.any (node: node == config.hostName) clusterCfg.worker.nodes;
      };
      options.isMember = lib.mkOption {
        readOnly = true;
        default = clusterCfg.worker.enabled || clusterCfg.controlplane.enabled;
      };
    }));

    apply = clusters: let
      memberOf = lib.pipe clusters [
        builtins.attrValues
        (builtins.filter (clusterCfg: clusterCfg.isMember))
      ];
      errors = lib.lists.optional (builtins.length memberOf > 1) "node ${config.hostName} cannot be member of multiple clusters: ${builtins.concatStringsSep ", " memberOf}";
    in
      lib.throwIf (errors != []) (builtins.concatStringsSep "\n" errors) clusters;
  };
}
