# Tier-1 assertions for the five `service-k8s*` aspects.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here activates and nothing joins a real cluster.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosBare` | `nixos` | all five aspects, and **no** cluster data at all |
# | `nixosCluster` | `nixos` | all five aspects, and one cluster that names this machine |
# | `darwinMgmt` | `darwin` | the two aspects that emit a `darwin` target |
# | `homeMgmt` | `homeManager` | the two aspects that emit a `homeManager` target |
#
# ## Why the bare subject matters most
#
# The old modules read cluster membership out of a meta option, and a machine with no data got
# nothing. `nixosBare` proves the port keeps that: five aspects load, the machine evaluates, and
# kubeadm and the load balancer write nothing.
#
# ## The cluster data below is a placeholder
#
# Every name, address and port here is invented for the test. Real cluster data belongs in
# `data/slots/`, never in a check file and never in an aspect.
#
# `allowedVersions` reads the subject's own package version, so the version assertion of
# `service-k8s` holds whatever nixpkgs ships. A literal prefix would break on the next bump.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);
  has = name: packages: lib.elem name (map lib.getName packages);

  k8sNames = [
    "service-k8s"
    "service-k8s-controlplane-lb"
    "service-k8s-kubeadm"
    "service-k8s-management"
    "service-k8s-node"
  ];

  nixosAspects = k8sNames;

  nixosModules = denLib.imports {
    class = "nixos";
    aspects = nixosAspects;
  };

  nixosBareSystem = bareNixos nixosModules;
  nixosBare = nixosBareSystem.config;

  # One cluster, three control-plane names, one worker name. This machine is `den-k8s`, a
  # control-plane node. The `nodes` set gives the addresses the old tree read out of the host graph.
  clusterOpinion =
    { config, ... }:
    {
      networking.hostName = "den-k8s";

      kdn.services.k8s.clusters.den = {
        enable = true;
        domain = "cluster.local";
        allowedVersions = [ config.kdn.services.k8s.packages.default.version ];
        apiserver.vrrp.masterNode = "den-k8s";
        apiserver.vrrp.id = 51;
        apiserver.vrrp.ipv4 = "10.10.0.10";
        apiserver.vrrp.ipv6 = "fd00:10::10";
        apiserver.port.internal = 6444;
        apiserver.port.shared = 6443;
        apiserver.interface = "eth0";
        apiserver.domain = "api.k8s.example";
        subnet.pod = [ "10.11.0.0/16" ];
        subnet.service = [ "10.12.0.0/16" ];
        controlplane.nodes = [
          "den-k8s"
          "den-k8s-2"
        ];
        worker.nodes = [ "den-k8s-3" ];
        nodes."den-k8s".addresses = [ "10.10.0.1/24" ];
        nodes."den-k8s-2".addresses = [ "10.10.0.2/24" ];
        nodes."den-k8s-3".addresses = [ "10.10.0.3/24" ];
      };
    };

  nixosClusterSystem = bareNixos (nixosModules ++ [ clusterOpinion ]);
  nixosCluster = nixosClusterSystem.config;

  darwinAspects = [
    "service-k8s"
    "service-k8s-management"
  ];

  darwinMgmtSystem = bareDarwinSystem (
    denLib.imports {
      class = "darwin";
      aspects = darwinAspects;
    }
  );
  darwinMgmt = darwinMgmtSystem.config;

  homeMgmtConfiguration = bareHomeConfiguration (
    denLib.imports {
      class = "homeManager";
      aspects = darwinAspects;
    }
  );
  homeMgmt = homeMgmtConfiguration.config;

  clusterCfg = nixosCluster.kdn.services.k8s.clusters.den;

  assertions = [
    # ---------------------------------------------------------------- instantiation
    {
      name = "the Kubernetes aspects instantiate with and without cluster data";
      expected = {
        bare = true;
        cluster = true;
        darwin = true;
        home = true;
      };
      actual = {
        bare = builtins.isString nixosBareSystem.config.system.build.toplevel.drvPath;
        cluster = builtins.isString nixosClusterSystem.config.system.build.toplevel.drvPath;
        darwin = builtins.isString darwinMgmt.system.build.toplevel.drvPath;
        home = builtins.isString homeMgmt.home.activationPackage.drvPath;
      };
    }
    {
      name = "each Kubernetes aspect emits the classes its old module had";
      expected = {
        service-k8s = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        service-k8s-controlplane-lb = [ "nixos" ];
        service-k8s-kubeadm = [ "nixos" ];
        service-k8s-management = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        service-k8s-node = [ "nixos" ];
      };
      actual = lib.mapAttrs (_: sorted) (lib.getAttrs k8sNames denLib.pairs);
    }

    # ---------------------------------------------------------------- service-k8s
    {
      name = "the cluster set is empty until a consumer fills it";
      expected = { };
      actual = nixosBare.kdn.services.k8s.clusters;
    }
    {
      name = "the four package options name the four upstream packages";
      expected = {
        default = "kubernetes";
        cilium-cli = "cilium-cli";
        containerd = "containerd";
        cri-tools = "cri-tools";
      };
      actual = lib.mapAttrs (_: lib.getName) nixosBare.kdn.services.k8s.packages;
    }

    # ---------------------------------------------------------------- the membership leaves
    {
      name = "the three membership leaves answer for this machine";
      expected = {
        controlplane = true;
        worker = false;
        isMember = true;
        name = "den";
      };
      actual = {
        controlplane = clusterCfg.controlplane.enabled;
        worker = clusterCfg.worker.enabled;
        isMember = clusterCfg.isMember;
        name = clusterCfg.name;
      };
    }
    {
      name = "a machine no cluster names belongs to no cluster";
      expected = {
        controlplane = false;
        worker = false;
        isMember = false;
      };
      actual =
        let
          outsider =
            (bareNixos (
              nixosModules
              ++ [
                clusterOpinion
                { networking.hostName = lib.mkForce "den-outsider"; }
              ]
            )).config.kdn.services.k8s.clusters.den;
        in
        {
          controlplane = outsider.controlplane.enabled;
          worker = outsider.worker.enabled;
          isMember = outsider.isMember;
        };
    }
    {
      name = "the backend address drops the prefix length, and an unnamed node has none";
      expected = {
        first = "10.10.0.1";
        second = "10.10.0.2";
        empty = null;
      };
      actual = {
        first = clusterCfg.nodes."den-k8s".backendAddress;
        second = clusterCfg.nodes."den-k8s-2".backendAddress;
        empty =
          (bareNixos (
            nixosModules
            ++ [
              clusterOpinion
              { kdn.services.k8s.clusters.den.nodes."den-k8s-4" = { }; }
            ]
          )).config.kdn.services.k8s.clusters.den.nodes."den-k8s-4".backendAddress;
      };
    }

    # ---------------------------------------------------------------- service-k8s-management
    {
      name = "the management aspect ships the distribution on nixos, and the filter drops it on darwin";
      # `pkgs.kubernetes` names Linux platforms only, and both darwin subjects pin
      # `aarch64-darwin`. So `common/filter-packages.nix` drops the distribution there. The aspect
      # still emits all three classes; only the package list differs.
      expected = {
        nixosKubernetes = true;
        nixosCilium = true;
        darwinKubernetes = false;
        homeKubernetes = false;
      };
      actual = {
        nixosKubernetes = has "kubernetes" nixosBare.environment.systemPackages;
        nixosCilium = has "cilium-cli" nixosBare.environment.systemPackages;
        darwinKubernetes = has "kubernetes" darwinMgmt.environment.systemPackages;
        homeKubernetes = has "kubernetes" homeMgmt.home.packages;
      };
    }

    # ---------------------------------------------------------------- service-k8s-node
    {
      name = "the node aspect loads the two bridge modules and sets the four forward sysctls";
      expected = {
        overlay = true;
        brNetfilter = true;
        sysctls = {
          "net.bridge.bridge-nf-call-ip6tables" = 1;
          "net.bridge.bridge-nf-call-iptables" = 1;
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };
        swap = [ ];
      };
      actual = {
        overlay = lib.elem "overlay" nixosBare.boot.kernelModules;
        brNetfilter = lib.elem "br_netfilter" nixosBare.boot.kernelModules;
        sysctls = lib.getAttrs [
          "net.bridge.bridge-nf-call-ip6tables"
          "net.bridge.bridge-nf-call-iptables"
          "net.ipv4.ip_forward"
          "net.ipv6.conf.all.forwarding"
        ] nixosBare.boot.kernel.sysctl;
        swap = nixosBare.swapDevices;
      };
    }
    {
      name = "the node aspect publishes the five Kubernetes state paths";
      expected = {
        configDirs = [ "/etc/kubernetes" ];
        configFiles = [ "/etc/default/kubelet" ];
        dataDirs = [
          "/var/lib/kubelet"
          "/var/lib/etcd"
          "/var/lib/containerd"
        ];
      };
      actual = {
        configDirs = nixosBare.kdn.disks.persist."sys/config".directories;
        configFiles = nixosBare.kdn.disks.persist."sys/config".files;
        dataDirs = nixosBare.kdn.disks.persist."sys/data".directories;
      };
    }
    {
      name = "the node aspect ships nerdctl and brings the network command set through its include";
      # The old module writes `kdn.toolset.network.enable = lib.mkDefault true`. The port turns that
      # write into an `includes` entry, so `nmap` and `ethtool` prove the include landed.
      expected = {
        nerdctl = true;
        nmap = true;
        ethtool = true;
      };
      actual = {
        nerdctl = has "nerdctl" nixosBare.environment.systemPackages;
        nmap = has "nmap" nixosBare.environment.systemPackages;
        ethtool = has "ethtool" nixosBare.environment.systemPackages;
      };
    }
    {
      name = "the node aspect writes no ZFS dataset while no disk aspect loads";
      # `disko` and `kdn.fs.zfs` belong to other aspects. A consumer that wants the container
      # dataset includes `disks` and `fs-zfs` too, and only then do the two writes appear.
      expected = {
        disko = false;
        fsZfs = false;
      };
      actual = {
        disko = nixosBare ? disko;
        fsZfs = (nixosBare.kdn.fs or { }) ? zfs;
      };
    }

    # ---------------------------------------------------------------- service-k8s-kubeadm
    {
      name = "kubeadm writes nothing while no cluster names this machine";
      expected = {
        cluster = { };
        containerd = false;
        kubelet = false;
        firewall = true;
      };
      actual = {
        cluster = nixosBare.kdn.services.k8s.kubeadm.config.cluster;
        containerd = nixosBare.virtualisation.containerd.enable;
        kubelet = nixosBare.systemd.services ? kubelet;
        firewall = nixosBare.networking.firewall.enable;
      };
    }
    {
      name = "kubeadm turns containerd on and opens the firewall once a cluster names this machine";
      expected = {
        containerd = true;
        configFile = true;
        firewall = false;
      };
      actual = {
        containerd = nixosCluster.virtualisation.containerd.enable;
        configFile = lib.hasSuffix "containerd-config.toml" (
          toString nixosCluster.virtualisation.containerd.configFile
        );
        firewall = nixosCluster.networking.firewall.enable;
      };
    }
    {
      name = "the cluster configuration names the endpoint, the two subnets and the DNS domain";
      expected = {
        apiVersion = "kubeadm.k8s.io/v1beta4";
        kind = "ClusterConfiguration";
        controlPlaneEndpoint = "api.k8s.example:6443";
        podSubnet = "10.11.0.0/16";
        serviceSubnet = "10.12.0.0/16";
        dnsDomain = "cluster.local";
        bindAddress = [
          {
            name = "bind-address";
            value = "::";
          }
        ];
      };
      actual =
        let
          cluster = nixosCluster.kdn.services.k8s.kubeadm.config.cluster;
        in
        {
          inherit (cluster) apiVersion kind controlPlaneEndpoint;
          podSubnet = cluster.networking.podSubnet;
          serviceSubnet = cluster.networking.serviceSubnet;
          dnsDomain = cluster.networking.dnsDomain;
          bindAddress = cluster.apiServer.extraArgs;
        };
    }
    {
      name = "the certificate names cover the endpoint and every node address";
      expected = [
        "10.10.0.1"
        "10.10.0.2"
        "10.10.0.3"
        "api.k8s.example"
      ];
      actual = sorted nixosCluster.kdn.services.k8s.kubeadm.config.cluster.apiServer.certSANs;
    }
    {
      name = "the kubelet unit keeps its working directory, its restart policy and its five paths";
      expected = {
        workingDirectory = "/var/lib/kubelet";
        restart = "always";
        restartSec = 10;
        environmentFiles = [
          "-/var/lib/kubelet/kubeadm-flags.env"
          "-/etc/default/kubelet"
        ];
        after = true;
        # nixpkgs writes its own default entries into the same `path` list, so the length is not 5.
        # The probe asks that each of the five entries of the aspect reaches the list.
        paths = true;
      };
      actual =
        let
          unit = nixosCluster.systemd.services.kubelet;
        in
        {
          workingDirectory = unit.serviceConfig.WorkingDirectory;
          restart = unit.serviceConfig.Restart;
          restartSec = unit.serviceConfig.RestartSec;
          environmentFiles = unit.serviceConfig.EnvironmentFile;
          after = lib.elem "network-online.target" unit.after;
          paths = lib.all (entry: lib.elem entry unit.path) [
            "/run/wrappers"
            "/root/.nix-profile"
            "/etc/profiles/per-user/root"
            "/nix/var/nix/profiles/default"
            "/run/current-system/sw"
          ];
        };
    }

    # ---------------------------------------------------------------- service-k8s-controlplane-lb
    {
      name = "the load balancer stays off while no cluster names this machine";
      expected = {
        keepalived = false;
        haproxy = false;
        scripts = [ ];
      };
      actual = {
        keepalived = nixosBare.services.keepalived.enable;
        haproxy = nixosBare.services.haproxy.enable;
        scripts = builtins.attrNames nixosBare.services.keepalived.vrrpScripts;
      };
    }
    {
      name = "the load balancer runs both daemons on a control-plane node";
      expected = {
        keepalived = true;
        haproxy = true;
        scriptSecurity = true;
        scripts = [ "kdn-den-check-apiserver" ];
        instances = [
          "kdn-den-apiserver-ipv4"
          "kdn-den-apiserver-ipv6"
        ];
      };
      actual = {
        keepalived = nixosCluster.services.keepalived.enable;
        haproxy = nixosCluster.services.haproxy.enable;
        scriptSecurity = nixosCluster.services.keepalived.enableScriptSecurity;
        scripts = builtins.attrNames nixosCluster.services.keepalived.vrrpScripts;
        instances = sorted (builtins.attrNames nixosCluster.services.keepalived.vrrpInstances);
      };
    }
    {
      name = "the VRRP master node holds the master state and the higher priority";
      expected = {
        state = "MASTER";
        priority = 101;
        routerId = 51;
        interface = "eth0";
        ipv4 = [ { addr = "10.10.0.10"; } ];
      };
      actual =
        let
          instance = nixosCluster.services.keepalived.vrrpInstances."kdn-den-apiserver-ipv4";
        in
        {
          state = instance.state;
          priority = instance.priority;
          routerId = instance.virtualRouterId;
          interface = instance.interface;
          ipv4 = map (v: { inherit (v) addr; }) instance.virtualIps;
        };
    }
    {
      name = "a node the cluster does not name master holds the backup state";
      expected = {
        state = "BACKUP";
        priority = 100;
      };
      actual =
        let
          backup =
            (bareNixos (
              nixosModules
              ++ [
                clusterOpinion
                { networking.hostName = lib.mkForce "den-k8s-2"; }
              ]
            )).config.services.keepalived.vrrpInstances."kdn-den-apiserver-ipv4";
        in
        {
          state = backup.state;
          priority = backup.priority;
        };
    }
    {
      name = "the haproxy backend dials every control-plane node on the internal port";
      expected = {
        first = true;
        second = true;
        worker = false;
        frontend = true;
      };
      actual =
        let
          text = nixosCluster.services.haproxy.config;
        in
        {
          first = lib.hasInfix "server den-k8s 10.10.0.1:6444 check verify none" text;
          second = lib.hasInfix "server den-k8s-2 10.10.0.2:6444 check verify none" text;
          worker = lib.hasInfix "den-k8s-3" text;
          frontend = lib.hasInfix "bind [::]:6443 v4v6" text;
        };
    }
    {
      name = "the keepalived script user and group exist on a control-plane node";
      expected = {
        user = true;
        group = true;
        systemUser = true;
      };
      actual = {
        user = nixosCluster.users.users ? keepalived_script;
        group = nixosCluster.users.groups ? keepalived_script;
        systemUser = nixosCluster.users.users.keepalived_script.isSystemUser;
      };
    }
  ];

  # ------------------------------------------------------------------ the coverage rows
  instantiatedBy = {
    service-k8s = "den-eval-k8s (bare nixos, bare darwin, bare home)";
    service-k8s-controlplane-lb = "den-eval-k8s (bare nixos, the cluster subject)";
    service-k8s-kubeadm = "den-eval-k8s (bare nixos, with and without cluster data)";
    service-k8s-management = "den-eval-k8s (bare nixos, bare darwin, bare home)";
    service-k8s-node = "den-eval-k8s (bare nixos)";
  };
in
{
  inherit assertions instantiatedBy;
}
