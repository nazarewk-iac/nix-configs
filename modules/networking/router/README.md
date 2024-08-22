A router setup used by `etra`.

# Scope

- WAN IPv4
    - [x] internet connectivity from router
- WAN IPv6
    - [x] internet connectivity from router
- LAN IPv4
    - [x] DHCP server
- LAN IPv6
    - [x] Router Advertisement
- Firewall
    - LAN IPv4
        - [x] internet connectivity
    - LAN IPv6
        - [x] internet connectivity
        - [x] ping devices from LAN
        - [x] ping devices from WAN
        - [x] route over link-local addresses (not using up public or generating private IPs)
- VLANs
    - [x] VLAN (pic) dedicated to kubernetes cluster
        - [x] confirm it works with direct connection (without switch)
        - [x] confirm it works through `Mokerlink 2G08110GT`:
            - works with `pic` VLAN as `tagged` and `1` (default/built-in) as `untagged` on all ports
- DNS
    - [ ] set up local DNS server
        - [ ] answer with local (DHCP?) hostnames

# materials

debugging info gist https://gist.github.com/nazarewk/49a76c2a63d4895cdcc6a14b82b02185

## examples / blog posts

- https://gist.github.com/mweinelt/b78f7046145dbaeab4e42bf55663ef44
- https://eldon.me/arch-linux-home-router-systemd-configuration/
- working snippet:
    - https://matrix.to/#/!tCyGickeVqkHsYjWnh:nixos.org/$WCyFnH_26PJX4lcbTDohzInJv0PLJRQzPKt4qFMeOJo?via=nixos.org&via=matrix.org&via=tchncs.de
    - https://git.sr.ht/~r-vdp/nixos-config/tree/f595662416269797ee2c917822133b5ae5119672/item/hosts/beelink/network.nix#L245

## documentation

- https://www.freedesktop.org/software/systemd/man/latest/networkd.conf.html
- https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html
- https://nixos.wiki/wiki/Systemd-networkd
- https://wiki.archlinux.org/title/Systemd-networkd