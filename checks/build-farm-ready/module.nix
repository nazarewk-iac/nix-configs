# The per-builder load responder the build farm does not have yet.
#
# HAProxy `agent-check` asks a builder one question: "how many builds may you take right now?"
# Today the answer is a static `maxConnections` number in `data/build-farm.nix`, except on `brys`,
# where a hand-written script answers `ready maxconn:N` from free RAM
# (`hosts-den/brys/llm.nix`). This module generalises that script: the answer comes from a state
# file, so one place decides and the service only reports it.
#
# The format matters. HAProxy's manual is explicit that only the agent may revert its own actions:
# a bare `maxconn:N` never clears a `DRAIN` the agent set earlier, so the service always emits
# `ready` first and shapes the curve with `maxconn` alone.
#
# The state file is the interface on purpose. A load sensor, an operator or a test writes a number;
# nothing else is implied, and the module holds no arithmetic of its own.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.build-farm-ready;

  respond = pkgs.writeShellScript "build-farm-ready" ''
    set -eu
    slots=$(cat ${lib.escapeShellArg cfg.stateFile} 2>/dev/null || echo ${toString cfg.maxSlots})
    case "$slots" in
      *[!0-9]*) slots=${toString cfg.maxSlots} ;;
    esac
    if [ -z "$slots" ]; then slots=${toString cfg.maxSlots}; fi
    # `maxconn:0` means UNLIMITED in HAProxy, not "no capacity": a server at 0 never fills and
    # `balance first` keeps sending to it. Zero slots must therefore be an admin state, and `drain`
    # is the one that means "finish what you have, take nothing new".
    if [ "$slots" -eq 0 ]; then
      printf 'drain\n'
    else
      printf 'ready maxconn:%s\n' "$slots"
    fi
  '';
in
{
  options.services.build-farm-ready = {
    enable = lib.mkEnableOption "the HAProxy agent-check responder for the build farm";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "The `agent-port` the proxy probes. It is not the SSH port.";
    };

    stateFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/build-farm-ready/maxconn";
      description = "The file that holds the current `maxconn` answer.";
    };

    maxSlots = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "The answer while the state file is missing or unreadable.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /run/build-farm-ready 0755 root root -"
      "f ${cfg.stateFile} 0644 root root - ${toString cfg.maxSlots}"
    ];

    # One listener, dual-stack: `TCP6-LISTEN` on `::` accepts IPv4-mapped connections too, while a
    # separate IPv4 listener would collide with it (`Address already in use`). A NixOS test network
    # is dual-stack and HAProxy picks the IPv6 address for a bare host name, so a plain
    # `TCP-LISTEN` (IPv4 only) shows `ECONNREFUSED` in `show stat`.
    systemd.services.build-farm-ready = {
      description = "Answer HAProxy agent-check with this builder's free build slots";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        # One script run per probe, so a changed state file is visible on the next probe with no
        # restart. `-d` keeps a log line per connection for the test and for an operator.
        ExecStart = "${pkgs.socat}/bin/socat -d TCP6-LISTEN:${toString cfg.port},fork,reuseaddr SYSTEM:${respond}";
        Restart = "always";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf config.networking.firewall.enable [ cfg.port ];
  };
}
