# One declaration of `kdn.services.k8s.clusters`, shared by every aspect that reads it.
#
# ## What the option means
#
# It describes each Kubernetes cluster this machine may join. One entry names the cluster's domain,
# its allowed control-plane versions, its API server endpoint, its two pod and service subnets, and
# the two node lists. Three read-only leaves answer the question every reader asks: is **this**
# machine a control-plane node, a worker, or neither.
#
# Five aspects read it: `service-k8s`, `service-k8s-management`, `service-k8s-node`,
# `service-k8s-kubeadm` and `service-k8s-controlplane-lb`. Three of them can load together in one
# `nixos` evaluation, so the declaration cannot be inline.
#
# ## Why a separate file, and why an import by path
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that reads this option writes one line in its target module:
#
#     imports = [ ../common/k8s-clusters.nix ];
#
# The shape copies ./host-name.nix and ./persist.nix.
#
# ## What this replaces
#
# The old tree declares the same schema outside the `kdn` prefix, and it reads two things a den
# aspect cannot reach:
#
# 1. **The machine's own name.** The old schema reads a meta option. This file reads
#    `config.kdn.hostName`, from ./host-name.nix.
# 2. **Another host's evaluated config.** The old tree reads each control-plane node's internal
#    address straight out of the flake's other host configurations. A den aspect holds no host
#    graph, so this file adds a `nodes.<name>` entry. A consumer fills the addresses in, and every
#    reader takes them from there.
#
# Personal data — a real domain, a real address, a real VRRP id — belongs in `data/slots/`, never in
# this file. See ../../../data/README.md.
#
# This file declares an option and sets no config, so it is safe in every class. It takes `config`
# and `lib` only, so it needs no `specialArgs` from the consumer.
{ config, lib, ... }:
{
  imports = [ ./host-name.nix ];

  options.kdn.services.k8s.clusters = lib.mkOption {
    default = { };
    description = ''
      One entry per Kubernetes cluster this machine may join. An empty set means the machine joins
      none, and every reader then writes nothing.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }@clusterArgs:
        let
          clusterCfg = clusterArgs.config;

          # An address may carry a prefix length. Every reader wants the bare address.
          stripPrefix =
            value:
            lib.pipe value [
              (lib.strings.splitString "/")
              lib.lists.head
            ];
        in
        {
          # This flag sits inside an `attrsOf submodule`, so the standalone check cannot reach it
          # and the aspect rule permits it. It marks one cluster of the set as live; it is not an
          # aspect switch.
          options.enable = lib.mkEnableOption "cluster configuration";

          options.name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "The cluster's own name. Every generated unit name starts with it.";
          };
          options.domain = lib.mkOption {
            type = lib.types.str;
            example = "cluster.local";
            description = "The cluster DNS domain.";
          };
          options.allowedVersions = lib.mkOption {
            type = with lib.types; listOf str;
            example = [ "1.33." ];
            description = ''
              Which control-plane versions this cluster accepts, as version prefixes. The first
              entry is the version kubeadm writes into its cluster configuration.
            '';
          };

          options.apiserver.vrrp.masterNode = lib.mkOption {
            type = lib.types.str;
            description = "Which node holds the VRRP master state. Every other node is a backup.";
          };
          options.apiserver.vrrp.id = lib.mkOption {
            type = lib.types.ints.u8;
            description = "The virtual router id. It must be unique on the link.";
          };
          options.apiserver.vrrp.ipv4 = lib.mkOption {
            type = lib.types.str;
            description = "The shared IPv4 address the API server answers on.";
          };
          options.apiserver.vrrp.ipv6 = lib.mkOption {
            type = lib.types.str;
            description = "The shared IPv6 address the API server answers on.";
          };
          options.apiserver.port.internal = lib.mkOption {
            type = lib.types.ints.u16;
            example = 6444;
            description = "The port one API server listens on, behind the load balancer.";
          };
          options.apiserver.port.shared = lib.mkOption {
            type = lib.types.ints.u16;
            example = 6443;
            description = "The port the load balancer listens on. Every client uses it.";
          };
          options.apiserver.interface = lib.mkOption {
            type = lib.types.str;
            example = "eth0";
            description = "Which interface carries the shared addresses.";
          };
          options.apiserver.domain = lib.mkOption {
            type = lib.types.str;
            description = "The name every client resolves to reach the API server.";
          };

          options.subnet.pod = lib.mkOption {
            type = with lib.types; listOf str;
            description = "The pod subnets, one per address family.";
          };
          options.subnet.service = lib.mkOption {
            type = with lib.types; listOf str;
            description = "The service subnets, one per address family.";
          };

          options.controlplane.nodes = lib.mkOption {
            type = with lib.types; listOf str;
            description = "The machine names that run the control plane.";
          };
          options.controlplane.enabled = lib.mkOption {
            readOnly = true;
            type = lib.types.bool;
            default = builtins.any (node: node == config.kdn.hostName) clusterCfg.controlplane.nodes;
            description = "True when this machine is a control-plane node of this cluster.";
          };
          options.worker.nodes = lib.mkOption {
            type = with lib.types; listOf str;
            description = "The machine names that run workloads.";
          };
          options.worker.enabled = lib.mkOption {
            readOnly = true;
            type = lib.types.bool;
            default = builtins.any (node: node == config.kdn.hostName) clusterCfg.worker.nodes;
            description = "True when this machine is a worker of this cluster.";
          };
          options.isMember = lib.mkOption {
            readOnly = true;
            type = lib.types.bool;
            default = clusterCfg.worker.enabled || clusterCfg.controlplane.enabled;
            description = "True when this machine belongs to this cluster in either role.";
          };

          options.nodes = lib.mkOption {
            default = { };
            description = ''
              The addresses of each node, keyed by machine name.

              The old tree reads these out of every other host's evaluated configuration. A den
              aspect holds no host graph, so a consumer states them here. An entry may name a
              machine that is in neither node list; every reader ignores it.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule (
                { ... }@nodeArgs:
                let
                  nodeCfg = nodeArgs.config;
                in
                {
                  options.addresses = lib.mkOption {
                    type = with lib.types; listOf str;
                    default = [ ];
                    example = [ "10.0.0.1/24" ];
                    description = ''
                      Every internal address of this node. A prefix length is allowed, and each
                      reader cuts it off. kubeadm puts all of them in the API server certificate.
                    '';
                  };
                  options.backendAddress = lib.mkOption {
                    type = with lib.types; nullOr str;
                    default = if nodeCfg.addresses == [ ] then null else stripPrefix (builtins.head nodeCfg.addresses);
                    defaultText = lib.literalMD "the first entry of `addresses`, with no prefix length";
                    description = ''
                      The one address the load balancer dials. `null` drops the node from the
                      balancer.

                      Give an IPv6 address with no brackets: haproxy adds none.
                    '';
                  };
                }
              )
            );
          };
        }
      )
    );

    apply =
      clusters:
      let
        memberOf = lib.pipe clusters [
          builtins.attrValues
          (builtins.filter (clusterCfg: clusterCfg.isMember))
        ];
        # The old message concatenates the cluster **values**, and that throws instead of reporting.
        # This one names them.
        names = map (clusterCfg: clusterCfg.name) memberOf;
        errors =
          lib.lists.optional (builtins.length memberOf > 1)
            "node ${config.kdn.hostName} cannot be member of multiple clusters: ${builtins.concatStringsSep ", " names}";
      in
      lib.throwIf (errors != [ ]) (builtins.concatStringsSep "\n" errors) clusters;
  };
}
