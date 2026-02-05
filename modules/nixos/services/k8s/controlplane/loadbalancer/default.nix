{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
}: let
  stripAddr = value:
    lib.pipe value [
      (lib.strings.splitString "/")
      lib.lists.head
    ];
in {
  config = lib.pipe kdnConfig.k8s.clusters [
    builtins.attrValues
    (builtins.filter (clusterCfg: clusterCfg.enable && clusterCfg.controlplane.enabled))
    (map (clusterCfg: {
      # based on https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md#keepalived-and-haproxy
      services.keepalived.vrrpScripts."kdn-${clusterCfg.name}-check-apiserver" = {
        script = lib.getExe (pkgs.writeShellApplication {
          name = "kdn-${clusterCfg.name}-check-apiserver-${kdnConfig.hostName}";
          text = let
            addr = ''https://localhost:${toString clusterCfg.apiserver.port.internal}'';
          in ''
            errorExit() {
                echo "*** $*" 1>&2
                exit 1
            }

            curl -sfk --max-time 2 ${addr}/healthz -o /dev/null || errorExit "Error GET ${addr}/healthz"
          '';
        });
        interval = 3;
        weight = -2;
        fall = 10;
        rise = 2;
      };
      services.keepalived.vrrpInstances = let
        baseCfg = {
          state =
            if clusterCfg.apiserver.vrrp.masterNode == kdnConfig.hostName
            then "MASTER"
            else "BACKUP";
          interface = clusterCfg.apiserver.interface;
          virtualRouterId = clusterCfg.apiserver.vrrp.id;
          priority =
            if clusterCfg.apiserver.vrrp.masterNode == kdnConfig.hostName
            then 101
            else 100;
          trackScripts = ["kdn-${clusterCfg.name}-check-apiserver"];
        };
      in {
        "kdn-${clusterCfg.name}-apiserver-ipv4" = lib.mkMerge [
          baseCfg
          {
            virtualIps = [{addr = clusterCfg.apiserver.vrrp.ipv4;}];
          }
        ];
        "kdn-${clusterCfg.name}-apiserver-ipv6" = lib.mkMerge [
          baseCfg
          {
            virtualIps = [{addr = clusterCfg.apiserver.vrrp.ipv6;}];
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

            ${lib.strings.concatMapStrings (
            host: let
              addr = stripAddr kdnConfig.self.hosts."${host}".kdn.networking.iface.internal.address.internal6;
              # haproxy doesn't use brackets around IPv6 addresses
            in ''
              server ${host} ${addr}:${toString clusterCfg.apiserver.port.internal} check verify none
            ''
          )
          clusterCfg.controlplane.nodes}
      '';
    }))
    (l:
      l
      ++ [
        {
          services.keepalived.enable = true;
          services.keepalived.enableScriptSecurity = true;
          services.keepalived.extraGlobalDefs = ''
            script_user keepalived_script
            max_auto_priority 90
          '';
          users.users.keepalived_script = {
            isSystemUser = true;
            group = "keepalived_script";
          };
          users.groups.keepalived_script = {};
        }
      ])
    lib.mkMerge
  ];
}
