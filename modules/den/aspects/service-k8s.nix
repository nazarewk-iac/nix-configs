# The four `services/k8s` modules of the old tree, as five den aspects.
#
# The old modules stay in place and keep working. This file is the parallel den implementation.
#
# | Aspect | Classes | What it does |
# |---|---|---|
# | `service-k8s` | nixos, darwin, homeManager | the cluster schema, the four package options, the version assertion |
# | `service-k8s-management` | nixos, darwin, homeManager | the `kubernetes` and `cilium-cli` commands, for a machine that administers a cluster |
# | `service-k8s-node` | nixos | what every node needs: the kernel modules, the sysctls, no swap, the state directories |
# | `service-k8s-kubeadm` | nixos | the kubeadm route: containerd, the kubelet unit, the cluster configuration |
# | `service-k8s-controlplane-lb` | nixos | keepalived and haproxy in front of the API servers |
#
# It follows https://joshrosso.com/c/nix-k8s/ .
#
# ## The cluster schema lives in ../common/k8s-clusters.nix
#
# Three of these aspects can load together in one `nixos` evaluation, and each one reads
# `kdn.services.k8s.clusters`. The module system rejects two inline declarations of one option, and
# it dedupes an import by path. So the schema is a file, and every target imports it.
#
# ## What the port changes
#
# 1. **Every `enable` goes.** Inclusion is the switch. The old defaults read cluster membership, and
#    a den consumer includes the aspects the machine needs instead. One data gate stays:
#    `service-k8s-kubeadm` and `service-k8s-controlplane-lb` write nothing until a cluster names
#    this machine, because neither one can name an endpoint without that data.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The host graph read goes.** The old kubeadm module and the old load-balancer module read each
#    other host's evaluated `kdn.networking.iface.internal.address`. A den aspect holds no host
#    graph, so a consumer fills `clusters.<name>.nodes.<machine>.addresses` in. See
#    ../common/k8s-clusters.nix.
# 4. **The old `kdn.services.k8s.node.enable` write becomes an `includes` entry**, and so does the
#    `kdn.toolset.network.enable` write. den collapses a diamond, so a name may repeat.
# 5. **The ZFS and disko writes become conditional.** The old node module writes
#    `kdn.fs.zfs.containers.fsname` and one `disko` dataset, and both need another area's option. A
#    den node writes them only when the consumer also includes `fs-zfs` and `disks`. The precedent
#    is `fs-luks-zfs`, which stopped writing `kdn.fs.zfs.enable` for the same reason.
# 6. **The Netbird write goes, for now.** The old kubeadm module turns one Netbird client off. No
#    networking aspect exists yet, so this file writes nothing there. A later batch restores it.
#    The old comment is worth keeping: the write must hold the **plain** priority, because the
#    baseline profile sets the same client to `lib.mkDefault true` and two `mkDefault` definitions
#    tie at 1000 and stop the evaluation.
# 7. **The containerd configuration file is a copy.** ./service-k8s/containerd-config.toml is a
#    byte-exact copy of the old file, because an aspect must not read the old tree.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence. The machine's own name comes from `kdn.hostName`, an
#    option of ../common/host-name.nix.
# 2. **No `enable` option.** Inclusion is the switch. The one `enable` left sits inside
#    `clusters.<name>`, an `attrsOf submodule`, so no consumer can reach it as an aspect switch.
# 3. **No custom module argument.** Each target module takes `config`, `options`, `lib` and `pkgs`
#    only.
{ kdn, ... }:
let
  # ------------------------------------------------------------------ shared helpers

  filterPackagesFor = lib: import ../common/filter-packages.nix { inherit lib; };

  # An address may carry a prefix length. Every reader below wants the bare address.
  stripPrefix =
    lib: value:
    lib.pipe value [
      (lib.strings.splitString "/")
      lib.lists.head
    ];

  # The cluster this machine belongs to, or `{ }` when it belongs to none. The schema's own `apply`
  # already refuses two memberships, so the first match is the only match.
  memberCluster =
    { config, lib }:
    lib.pipe config.kdn.services.k8s.clusters [
      builtins.attrValues
      (lib.lists.findFirst (clusterCfg: clusterCfg.isMember) { })
    ];

  # ------------------------------------------------------------------ service-k8s

  rootDeclaration =
    { lib, pkgs, ... }:
    {
      imports = [ ../common/k8s-clusters.nix ];

      options.kdn.services.k8s.packages.default = lib.mkPackageOption pkgs "kubernetes" { };
      options.kdn.services.k8s.packages.cilium-cli = lib.mkPackageOption pkgs "cilium-cli" { };
      options.kdn.services.k8s.packages.containerd = lib.mkPackageOption pkgs "containerd" { };
      options.kdn.services.k8s.packages.cri-tools = lib.mkPackageOption pkgs "cri-tools" { };
    };

  # The version gate. It forces the package version only when a cluster is live, so a machine with
  # no cluster data pays nothing.
  rootTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ rootDeclaration ];

      assertions = [
        {
          assertion = lib.pipe config.kdn.services.k8s.clusters [
            builtins.attrValues
            (builtins.filter (clusterCfg: clusterCfg.enable))
            (map (
              clusterCfg:
              builtins.any (
                allowed: lib.hasPrefix allowed config.kdn.services.k8s.packages.default.version
              ) clusterCfg.allowedVersions
            ))
            (builtins.all lib.id)
          ];
          message = "Kubernetes cluster is pinned to unsupported version!";
        }
      ];
    };

  # ------------------------------------------------------------------ service-k8s-management

  managementPackages =
    {
      config,
      lib,
      pkgs,
    }:
    filterPackagesFor lib [
      config.kdn.services.k8s.packages.default
      config.kdn.services.k8s.packages.cilium-cli
    ];

  managementNixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      environment.systemPackages = managementPackages { inherit config lib pkgs; };
    };

  managementDarwin = managementNixos;

  managementHome =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages = managementPackages { inherit config lib pkgs; };
    };

  # ------------------------------------------------------------------ service-k8s-node

  nodeDeclaration =
    { config, lib, ... }:
    {
      imports = [ ../common/k8s-clusters.nix ];

      options.kdn.services.k8s.node.packages.default = lib.mkOption {
        type = lib.types.package;
        default = config.kdn.services.k8s.packages.default;
        defaultText = lib.literalExpression "config.kdn.services.k8s.packages.default";
        description = "The Kubernetes distribution this node runs.";
      };
      options.kdn.services.k8s.node.packages.containerd = lib.mkOption {
        type = lib.types.package;
        default = config.kdn.services.k8s.packages.containerd;
        defaultText = lib.literalExpression "config.kdn.services.k8s.packages.containerd";
        description = "The container runtime this node runs.";
      };
      options.kdn.services.k8s.node.packages.cri-tools = lib.mkOption {
        type = lib.types.package;
        default = config.kdn.services.k8s.packages.cri-tools;
        defaultText = lib.literalExpression "config.kdn.services.k8s.packages.cri-tools";
        description = "The CRI command set this node ships.";
      };
    };

  nodeTarget =
    {
      config,
      options,
      lib,
      pkgs,
      ...
    }:
    let
      # The `disks` aspect declares `kdn.disks.zpool-main`, and the `fs-zfs` aspect declares
      # `kdn.fs.zfs.containers`. Neither is a dependency of a Kubernetes node, so each write waits
      # for the option to exist. `lib.optionalAttrs` drops the whole block when it does not, so no
      # undeclared option ever reaches the merge.
      hasDisks = ((options.kdn or { }).disks or { }) ? zpool-main;
      hasFsZfs = (((options.kdn or { }).fs or { }).zfs or { }) ? containers;
    in
    {
      imports = [
        nodeDeclaration
        ../common/persist.nix
      ];

      config = lib.mkMerge [
        {
          boot.kernelModules = [
            "overlay"
            "br_netfilter"
          ];
          boot.kernel.sysctl = {
            "net.bridge.bridge-nf-call-iptables" = 1;
            "net.bridge.bridge-nf-call-ip6tables" = 1;
            "net.ipv4.ip_forward" = 1;
            "net.ipv6.conf.all.forwarding" = 1;
          };
          # The kubelet refuses to start with swap on.
          swapDevices = lib.mkForce [ ];

          environment.systemPackages = filterPackagesFor lib (
            with pkgs;
            [
              nerdctl
            ]
          );

          kdn.disks.persist."sys/config".directories = [
            "/etc/kubernetes"
          ];
          kdn.disks.persist."sys/config".files = [
            "/etc/default/kubelet"
          ];
          kdn.disks.persist."sys/data".directories = [
            "/var/lib/kubelet"
            "/var/lib/etcd"
            "/var/lib/containerd"
          ];
        }
        (lib.optionalAttrs hasFsZfs {
          kdn.fs.zfs.containers.fsname = "${config.kdn.disks.zpool-main.name}/containerd/storage";
        })
        (lib.optionalAttrs hasDisks {
          disko.devices.zpool."${config.kdn.disks.zpool-main.name}".datasets."containerd/storage" = {
            type = "zfs_volume";
            options."com.sun:auto-snapshot" = "false";
            # It creates the parents. The volume type misses that.
            extraArgs = [ "-p" ];
          };
        })
      ];
    };

  # ------------------------------------------------------------------ service-k8s-kubeadm

  kubeadmDeclaration =
    { lib, pkgs, ... }:
    {
      imports = [ ../common/k8s-clusters.nix ];

      options.kdn.services.k8s.kubeadm.config.cluster = lib.mkOption {
        type = (pkgs.formats.json { }).type;
        default = { };
        description = ''
          The kubeadm `ClusterConfiguration`. This aspect fills it from the cluster entry that names
          this machine. It stays empty when no entry does.
        '';
      };
    };

  kubeadmTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nCfg = config.kdn.services.k8s.node;
      clusterCfg = memberCluster { inherit config lib; };
    in
    {
      imports = [ kubeadmDeclaration ];

      # The data gate. kubeadm needs an endpoint, a version and two subnets, and no default can
      # invent them. So the whole target waits for a cluster entry that names this machine.
      config = lib.mkIf (clusterCfg != { }) (
        lib.mkMerge [
          {
            # TODO: address this
            networking.firewall.enable = false;

            virtualisation.containerd.enable = true;
            virtualisation.containerd.configFile = ./service-k8s/containerd-config.toml;

            environment.systemPackages = filterPackagesFor lib [
              nCfg.packages.default
              nCfg.packages.cri-tools
              nCfg.packages.containerd
            ];
          }
          {
            systemd.services.kubelet = {
              enable = true;
              description = "kubelet";

              serviceConfig = {
                WorkingDirectory = "/var/lib/kubelet";
                ExecStart = "${nCfg.packages.default}/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS";
                Environment = [
                  "\"KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf\""
                  "\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\""
                ];
                EnvironmentFile = [
                  "-/var/lib/kubelet/kubeadm-flags.env"
                  "-/etc/default/kubelet"
                ];
                Restart = "always";
                StartLimitInterval = 0;
                RestartSec = 10;
              };
              wantedBy = [ "network-online.target" ];
              after = [ "network-online.target" ];
              path = [
                # TODO: could probably put concrete dependencies in here?
                "/run/wrappers"
                "/root/.nix-profile"
                "/etc/profiles/per-user/root"
                "/nix/var/nix/profiles/default"
                "/run/current-system/sw"
              ];
            };
          }
          {
            kdn.services.k8s.kubeadm.config.cluster = {
              apiVersion = "kubeadm.k8s.io/v1beta4";
              kind = "ClusterConfiguration";
              kubernetesVersion = builtins.head clusterCfg.allowedVersions;
              controlPlaneEndpoint = "${clusterCfg.apiserver.domain}:${toString clusterCfg.apiserver.port.shared}";
              networking.podSubnet = builtins.concatStringsSep "," clusterCfg.subnet.pod;
              networking.serviceSubnet = builtins.concatStringsSep "," clusterCfg.subnet.service;
              networking.dnsDomain = clusterCfg.domain;
              apiServer.certSANs = [
                clusterCfg.apiserver.domain
              ]
              ++ lib.pipe (clusterCfg.controlplane.nodes ++ clusterCfg.worker.nodes) [
                lib.lists.unique
                (map (hostname: clusterCfg.nodes.${hostname}.addresses or [ ]))
                builtins.concatLists
                (map (stripPrefix lib))
                (builtins.sort (a: b: a < b))
              ];
              apiServer.extraArgs = [
                {
                  name = "bind-address";
                  value = "::";
                }
              ];
            };
          }
        ]
      );
    };

  # ------------------------------------------------------------------ service-k8s-controlplane-lb

  # It follows
  # https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md#keepalived-and-haproxy
  loadBalancerTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostName = config.kdn.hostName;

      live = lib.pipe config.kdn.services.k8s.clusters [
        builtins.attrValues
        (builtins.filter (clusterCfg: clusterCfg.enable && clusterCfg.controlplane.enabled))
      ];

      perCluster = clusterCfg: {
        services.keepalived.vrrpScripts."kdn-${clusterCfg.name}-check-apiserver" = {
          script = lib.getExe (
            pkgs.writeShellApplication {
              name = "kdn-${clusterCfg.name}-check-apiserver-${hostName}";
              text =
                let
                  addr = "https://localhost:${toString clusterCfg.apiserver.port.internal}";
                in
                ''
                  errorExit() {
                      echo "*** $*" 1>&2
                      exit 1
                  }

                  curl -sfk --max-time 2 ${addr}/healthz -o /dev/null || errorExit "Error GET ${addr}/healthz"
                '';
            }
          );
          interval = 3;
          weight = -2;
          fall = 10;
          rise = 2;
        };

        services.keepalived.vrrpInstances =
          let
            isMaster = clusterCfg.apiserver.vrrp.masterNode == hostName;
            baseCfg = {
              state = if isMaster then "MASTER" else "BACKUP";
              interface = clusterCfg.apiserver.interface;
              virtualRouterId = clusterCfg.apiserver.vrrp.id;
              priority = if isMaster then 101 else 100;
              trackScripts = [ "kdn-${clusterCfg.name}-check-apiserver" ];
            };
          in
          {
            "kdn-${clusterCfg.name}-apiserver-ipv4" = lib.mkMerge [
              baseCfg
              {
                virtualIps = [ { addr = clusterCfg.apiserver.vrrp.ipv4; } ];
              }
            ];
            "kdn-${clusterCfg.name}-apiserver-ipv6" = lib.mkMerge [
              baseCfg
              {
                virtualIps = [ { addr = clusterCfg.apiserver.vrrp.ipv6; } ];
              }
            ];
          };

        services.haproxy.enable = true;
        services.haproxy.config = ''
          #---------------------------------------------------------------------
          # Global settings
          #---------------------------------------------------------------------
          global
              log stdout format raw local0

          #---------------------------------------------------------------------
          # common defaults that all the 'listen' and 'backend' sections will
          # use if not designated in their block
          #---------------------------------------------------------------------
          defaults
              mode                    http
              log                     global
              option                  httplog
              option                  dontlognull
              option http-server-close
              option forwardfor       except 127.0.0.0/8
              option                  redispatch
              retries                 1
              timeout http-request    10s
              timeout queue           20s
              timeout connect         5s
              timeout client          35s
              timeout server          35s
              timeout http-keep-alive 10s
              timeout check           10s

          #---------------------------------------------------------------------
          # apiserver frontend which proxys to the control plane nodes
          #---------------------------------------------------------------------
          frontend kdn-${clusterCfg.name}-apiserver-frontend
              bind [::]:${toString clusterCfg.apiserver.port.shared} v4v6
              mode tcp
              option tcplog
              default_backend kdn-${clusterCfg.name}-apiserver-backend
          #---------------------------------------------------------------------
          # round robin balancing for apiserver
          #---------------------------------------------------------------------
          backend kdn-${clusterCfg.name}-apiserver-backend
              option httpchk

              http-check connect ssl
              http-check send meth GET uri /healthz
              http-check expect status 200

              mode tcp
              balance     roundrobin

              ${lib.pipe clusterCfg.controlplane.nodes [
                (map (host: {
                  inherit host;
                  addr = clusterCfg.nodes.${host}.backendAddress or null;
                }))
                (builtins.filter (entry: entry.addr != null))
                # haproxy takes an IPv6 address with no brackets.
                (map (entry: ''
                  server ${entry.host} ${entry.addr}:${toString clusterCfg.apiserver.port.internal} check verify none
                ''))
                lib.strings.concatStrings
              ]}
        '';
      };
    in
    {
      imports = [ ../common/k8s-clusters.nix ];

      # The top-level attribute names of `config` stay static, `services` and `users`. A
      # `lib.mkMerge` at the top level makes the module system read `config` to learn which options
      # this module defines. That read reaches `live`, which reads
      # `config.kdn.services.k8s.clusters`, and the evaluation recurses. So each `mkMerge` sits one
      # level down, under a fixed name.
      config = {
        services = lib.mkMerge (
          map (clusterCfg: (perCluster clusterCfg).services) live
          ++ [
            (lib.mkIf (live != [ ]) {
              keepalived.enable = true;
              keepalived.enableScriptSecurity = true;
              keepalived.extraGlobalDefs = ''
                script_user keepalived_script
                max_auto_priority 90
              '';
            })
          ]
        );

        users = lib.mkIf (live != [ ]) {
          users.keepalived_script = {
            isSystemUser = true;
            group = "keepalived_script";
          };
          groups.keepalived_script = { };
        };
      };
    };
in
{
  # ------------------------------------------------------------------ service-k8s
  kdn.service-k8s.nixos = rootTarget;
  kdn.service-k8s.darwin = rootTarget;
  kdn.service-k8s.homeManager = rootTarget;

  # ------------------------------------------------------------------ service-k8s-management
  kdn.service-k8s-management.includes = [ kdn.service-k8s ];

  kdn.service-k8s-management.nixos = managementNixos;
  kdn.service-k8s-management.darwin = managementDarwin;
  kdn.service-k8s-management.homeManager = managementHome;

  # ------------------------------------------------------------------ service-k8s-node
  kdn.service-k8s-node.includes = [
    kdn.service-k8s
    kdn.toolset-network
  ];

  kdn.service-k8s-node.nixos = nodeTarget;

  # ------------------------------------------------------------------ service-k8s-kubeadm
  kdn.service-k8s-kubeadm.includes = [ kdn.service-k8s-node ];

  kdn.service-k8s-kubeadm.nixos = kubeadmTarget;

  # ------------------------------------------------------------------ service-k8s-controlplane-lb
  kdn.service-k8s-controlplane-lb.includes = [ kdn.service-k8s ];

  kdn.service-k8s-controlplane-lb.nixos = loadBalancerTarget;
}
