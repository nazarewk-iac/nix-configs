# Option schema for kdn-ssh-access: the host connectivity graph.
#
# Usable three ways:
#   - as a submodule type   -> `pkgs.kdn.kdn-ssh-access.configType` (embed in any NixOS/HM config)
#   - for validated config   -> `pkgs.kdn.kdn-ssh-access.withModule { … }` (evalModules -> withConfig)
#   - imported by the slot   -> `modules/slots/ssh-access` wraps this in its `kdn.ssh-access` option
#
# `config.errors` holds eval-time edge-validation messages (a stand-in for a static enum on the
# dynamically-valued `from`, which is "internet" / "lan" / any defined host name).
{ lib, config, ... }:
let
  cfg = config;

  strOpt = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };

  uplinkType = lib.types.submodule {
    options = {
      ipv4 = strOpt;
      ipv6 = strOpt;
      ipv4File = strOpt;
      ipv6File = strOpt;
    };
  };

  edgeType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "`internet` (entry from anywhere), `lan` (direct, on that LAN), or a host name (relay hop).";
      };
      uplink = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "For `from = internet`: uplink whose (WAN) address reaches this host.";
      };
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Literal address of this host as seen from `from` (resolved on that hop for relays).";
      };
      addressFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Edge weight; a path's cost is the sum, lower is preferred.";
      };
    };
  };

  hostType = lib.types.submodule {
    options = {
      user = strOpt;
      hostKeyAlias = strOpt;
      reachedFrom = lib.mkOption {
        type = lib.types.listOf edgeType;
        default = [ ];
        description = "Edges describing how this host is reached.";
      };
    };
  };

  knownFrom = [
    "internet"
    "lan"
  ]
  ++ builtins.attrNames cfg.hosts;
  edgeErrors = lib.concatLists (
    lib.mapAttrsToList (
      hn: h:
      lib.concatLists (
        lib.imap0 (
          i: e:
          let
            loc = "hosts.${hn}.reachedFrom.[${toString i}]";
          in
          lib.optional (
            !(builtins.elem e.from knownFrom)
          ) ''${loc}: from="${e.from}" must be "internet", "lan", or a defined host''
          ++ lib.optional (
            e.address == null && e.addressFile == null && e.uplink == null
          ) "${loc}: needs address, addressFile, or uplink"
          ++ lib.optional (
            e.uplink != null && e.from != "internet"
          ) ''${loc}: uplink applies only to from="internet"''
        ) h.reachedFrom
      )
    ) cfg.hosts
  );
in
{
  options = {
    defaults.user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "kdn";
    };
    defaults.identityFile = strOpt;
    defaults.lanProbeTimeoutMs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1000;
    };
    defaults.cacheTtlSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
    };
    defaults.maxHops = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
    };
    defaults.ipVersionPreference = lib.mkOption {
      type = lib.types.enum [
        "ipv6-first"
        "ipv4-first"
      ];
      default = "ipv6-first";
    };

    identityAgentPatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra Host patterns forced to $SSH_AUTH_SOCK (e.g. direct LAN FQDNs/ranges).";
    };

    uplinks = lib.mkOption {
      type = lib.types.attrsOf uplinkType;
      default = { };
    };
    hosts = lib.mkOption {
      type = lib.types.attrsOf hostType;
      default = { };
      description = "The host graph; each name is also the `kdn-<name>` ssh alias.";
    };

    errors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      readOnly = true;
      description = "Eval-time edge-validation messages (empty = valid).";
    };
  };

  config.errors = edgeErrors;
}
