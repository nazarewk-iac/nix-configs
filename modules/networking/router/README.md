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
        - [ ] internet connectivity
        - [ ] ping devices from LAN
        - [ ] ping devices from WAN

# materials

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