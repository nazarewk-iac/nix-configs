# The `service-rustdesk` aspect. It runs the RustDesk server suite: `hbbs` (the ID / rendezvous
# server) and `hbbr` (the relay server), both from `pkgs.rustdesk-server`.
#
# ## What it does
#
# It turns on `services.rustdesk-server` with both the signal and the relay daemon. It states no
# key: `hbbs` generates its `id_ed25519` key pair into its state directory on first start, and
# `hbbr` reads the public half from the same directory.
#
# ## The firewall
#
# The aspect opens nothing by default. A hub that fronts the service with a public forwarder (see
# the `net-rustdesk-forward` aspect) keeps these ports closed on its own interfaces; NetBird mesh
# peers reach them through the router's trusted interface. Set
# `kdn.services.rustdesk.openFirewall = true` only on a host that serves the ports directly.
#
# ## The relay advertisement
#
# `kdn.services.rustdesk.relayHosts` names the relay servers `hbbs` advertises to clients. Keep it
# empty when clients derive the relay from the address they connected to (a forward that maps the
# whole port range identically does that). Name the public FQDN there when clients must relay
# through the public entrypoint.
{ ... }:
{
  kdn.service-rustdesk.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.rustdesk;
    in
    {
      options.kdn.services.rustdesk = {
        relayHosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "rustdesk.example.com" ];
          description = ''
            The relay servers `hbbs` advertises to clients, passed to `--relay-servers`.
            An empty list advertises nothing and lets the client derive the relay from
            the address it used to reach the ID server.
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open TCP 21115-21119 and UDP 21116 on this host's firewall.
          '';
        };
      };

      config = {
        services.rustdesk-server = {
          enable = true;
          inherit (cfg) openFirewall;
          signal.relayHosts = cfg.relayHosts;
        };

        # The nixpkgs module appends `--relay-servers <joined>` unconditionally, and `hbbs`
        # aborts when the flag carries no value. Drop the flag when nothing is advertised.
        systemd.services.rustdesk-signal.serviceConfig.ExecStart = lib.mkIf (cfg.relayHosts == [ ]) (
          lib.mkForce "${config.services.rustdesk-server.package}/bin/hbbs"
        );
      };
    };
}
