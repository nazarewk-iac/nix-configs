# kdn's own host connectivity graph for `kdn.ssh-access`.
#
# The `kdn-` prefix marks this as private data, not a shared or reusable module: it describes one
# person's machines and networks. Another user of this repo writes their own graph file and imports
# that instead. The reusable parts are the slot (`default.nix`) and the schema
# (`packages/kdn-ssh-access/module.nix`).
#
# This file is NOT auto-loaded: `modules/slots/default.nix` only picks up `*/default.nix`.
# Import it explicitly from a host's `mkSlots` call. The host keeps `enable` and everything
# machine-local (for example `defaults.identityFile`):
#
#   slots = kdnConfig.self.mkSlots {
#     inherit pkgs;
#     imports = [ "${kdnConfig.self}/modules/slots/ssh-access/kdn-graph.nix" ];
#     kdn.ssh-access.enable = true;
#   };
#
# The graph is machine-independent. An edge says how a host is reached FROM a place, not from one
# specific machine, so every machine shares the same data. Each machine finds its own position
# through the `lan` and `internet` edges: a `lan` edge only wins when the machine sits on that LAN.
#
# Topology: drek = primary edge/WAN router (it forwards to etra); etra = secondary homelab router;
# brys, oams, and anji sit on etra's ethernet and on drek's WiFi (etra is preferred).
# A lower `priority` is tried first. The commented relay edges need each target's address as the
# relay host sees it; fill one in to unlock that path.
#
# A relay edge is NOT probed. The tool probes the first hop only, because it cannot see the
# network of the relay host. So the priority alone decides which final address a relay dials, and
# a name that the relay cannot resolve fails only at connect time. etra does not answer its own
# `lan.etra.net.int.kdn.im` zone yet, so every `from = "etra"` edge puts the static mgmt address
# first and keeps the FQDN as the next entry, for when that zone works. anji holds no static
# address, so its relay path depends on that zone alone.
{ ... }:
{
  kdn.ssh-access = {
    # Direct connections to the personal LANs use the OpenSSH (hardware token) agent. Without
    # this, a machine with another default agent (for example the macOS or 1Password agent)
    # offers no usable key.
    identityAgentPatterns = [
      "*.kdn.im"
      "192.168.41.*" # drek lan
      "192.168.73.*" # etra lan
      "192.168.252.*" # etra mgmt
    ];

    # The ISP addresses change, so they are read from files at connect time, never baked in.
    uplinks.home.ipv4File = "/run/configs/networking/ipv4/network/isp/uplink/address/client";
    uplinks.home.ipv6File = "/run/configs/networking/ipv6/network/isp/uplink/address/client";

    # Prefer an FQDN or a port forward.
    #
    # Add an IP literal only for an address that cannot move. brys, oams, and anji take a DHCP
    # lease on the `lan` net (etra's pool is 192.168.73.32-254, with no reservation for them), so
    # a literal for those goes stale with no warning and every route through it then fails with
    # `No route to host`. The mgmt addresses are the exception — see brys below.
    hosts = {
      moss.hostKeyAlias = "moss";
      moss.reachedFrom = [
        {
          from = "internet";
          address = "moss.kdn.im.";
          priority = 30;
        }
      ];

      etra.hostKeyAlias = "etra";
      etra.reachedFrom = [
        {
          from = "internet";
          uplink = "home";
          port = 40878;
          priority = 20;
        }
        # { from = "moss"; address = "<etra as moss sees it, NetBird>"; priority = 60; }
      ];

      drek.user = "root";
      drek.hostKeyAlias = "drek";
      drek.reachedFrom = [
        {
          from = "internet";
          uplink = "home";
          port = 33698;
          priority = 25;
        }
        # { from = "moss"; address = "<drek as moss sees it, NetBird>"; priority = 65; }
      ];

      oams.hostKeyAlias = "oams";
      oams.reachedFrom = [
        {
          from = "lan";
          address = "oams.lan.etra.net.int.kdn.im.";
          priority = 10;
        }
        # oams assigns 192.168.252.33/24 to its own `mgmt` VLAN profile (hosts/oams/default.nix,
        # networkmanager profile vlan-mgmt) next to the DHCP lease. The address is static, so a
        # literal is safe. It needs no DNS and no lease, so it answers when both of those are down.
        {
          from = "lan";
          address = "192.168.252.33";
          priority = 12;
        }
        # etra cannot resolve the FQDN yet, so the mgmt address goes first here.
        #
        # Both relay entries failed on 2026-09-08: etra answered `No route to host` for .33, and
        # the FQDN accepted TCP on etra but sent no sshd banner. Check oams's mgmt VLAN on the
        # switch first. Note that each failed attempt authenticates to etra again, so it costs one
        # more hardware-key tap.
        {
          from = "etra";
          address = "192.168.252.33";
          priority = 40;
        }
        {
          from = "etra";
          address = "oams.lan.etra.net.int.kdn.im.";
          priority = 43;
        }
        # { from = "drek"; address = "<oams on drek WiFi>"; priority = 50; }
        # { from = "moss"; address = "<oams as moss sees it, NetBird>"; priority = 70; }
      ];

      brys.hostKeyAlias = "brys";
      brys.reachedFrom = [
        {
          from = "lan";
          address = "brys.lan.etra.net.int.kdn.im.";
          priority = 10;
        }
        # The mgmt address is static, so a literal is safe here. brys assigns it to its own `mgmt`
        # interface (hosts/brys/default.nix, kdn.networking.ifaces."mgmt"), and etra reserves it
        # (hosts/etra/default.nix, router.nets.mgmt) outside the DHCP pool (.128-.159). It needs
        # no DNS and no lease, so it answers when both of those are down.
        #
        # oams also holds 192.168.252.33/24, so for oams this is a direct route with no relay.
        # mgmt is a VLAN on the same physical link as `lan`, so it adds no protection against a
        # fault on brys itself — only against a DNS or lease failure.
        {
          from = "lan";
          address = "192.168.252.32";
          priority = 12;
        }
        # etra cannot resolve the FQDN yet, so the mgmt address goes first here.
        {
          from = "etra";
          address = "192.168.252.32";
          priority = 40;
        }
        {
          from = "etra";
          address = "brys.lan.etra.net.int.kdn.im.";
          priority = 43;
        }
        # { from = "drek"; address = "<brys on drek WiFi>"; priority = 50; }
      ];

      anji.hostKeyAlias = "anji";
      anji.reachedFrom = [
        {
          from = "lan";
          address = "anji.lan.etra.net.int.kdn.im.";
          priority = 10;
        }
        # anji has no static address on any of these nets, so a relay through etra depends on the
        # `lan.etra` zone. Give anji a mgmt address, or fix the zone, to make this path reliable.
        {
          from = "etra";
          address = "anji.lan.etra.net.int.kdn.im.";
          priority = 40;
        }
        # { from = "drek"; address = "<anji on drek WiFi>"; priority = 50; }
      ];
    };
  };
}
