---
type: Reference
description: How to log into each network device and run commands against it.
timestamp: 2026-09-28T21:45:00+02:00
authored_by: agent
---

# Network devices

This file records how to reach each switch or router and how to run a command against it.
See [network-topology.md](network-topology.md) for the links and the VLANs.

## `coll` — TP-Link SG3428X-M2

`coll` is a TP-Link Omada-class switch. It runs a Cisco-like CLI. It has **no SSH exec
channel**: a plain `ssh host "command"` fails with `exec request failed on channel 0`. You
must open an interactive shell and feed the commands on stdin.

The switch also needs an old RSA key and old crypto. The key is `sg3428x-switch`, stored in
KeePassXC. Load it into the SSH agent first (the file `~/.ssh/id_rsa_coll.pub` holds the
public half only):

```sh
# in KeePassXC, add the private key "sg3428x-switch" to the SSH agent
ssh-add -l | grep sg3428x-switch   # confirm it is loaded
```

Run one or more commands with a CR-terminated stdin pipe. `-tt` forces a pty. The CR
(`\r`) line ending is required; a plain `\n` makes the switch echo the commands on one
line and run none of them:

```sh
{ printf 'enable\r'; sleep 1; printf 'terminal length 0\r'; sleep 1; \
  printf 'show vlan\r'; sleep 2; printf 'exit\r'; sleep 1; } \
| ssh -tt \
    -o WarnWeakCrypto=no \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -o HostkeyAlgorithms=+ssh-rsa \
    -o ControlMaster=no -o ControlPath=none \
    -i ~/.ssh/id_rsa_coll.pub \
    coll.mgmt.etra.net.int.kdn.im
```

A shell function for repeated use:

```sh
coll() {
  { printf 'enable\r'; sleep 1; printf 'terminal length 0\r'; sleep 1
    for c in "$@"; do printf '%s\r' "$c"; sleep 2; done
    printf 'exit\r'; sleep 1
  } | ssh -tt -o WarnWeakCrypto=no -o PubkeyAcceptedAlgorithms=+ssh-rsa \
        -o HostkeyAlgorithms=+ssh-rsa -o ControlMaster=no -o ControlPath=none \
        -i ~/.ssh/id_rsa_coll.pub coll.mgmt.etra.net.int.kdn.im
}
coll 'show vlan' 'show mac address-table' 'show lldp neighbor'
```

Useful commands: `show running-config`, `show vlan`, `show interface status`,
`show mac address-table`, `show lldp neighbor`, `show ip interface brief`.

## `talt` — MikroTik CRS312-4C+8XG

`talt` runs RouterOS. It accepts a normal SSH command. Reach it through the `brys` jump
host:

```sh
ssh -J brys talt.lan.etra.net.int.kdn.im '/interface bridge print'
```

Useful commands: `/export`, `/interface bridge vlan print detail`,
`/interface bridge host print detail`, `/interface bridge port print detail`,
`/ip address print`, `/ip neighbor print detail`, `/tool sniffer quick`.

## `etra` — router (NixOS)

`etra` is a NixOS host and accepts a normal SSH command:

```sh
ssh etra 'ip -br addr'
```

Useful commands: `ip -br addr`, `ip route`, `ip neigh`, `bridge vlan show`,
`cat /proc/net/bonding/lan`, `sudo cat /var/lib/knot/lan.etra.net.int.kdn.im.zone`,
`sudo tcpdump -i any -n -e arp`.

## `quip` — Zyxel XGS1250-12

`quip` has **no SSH and no telnet**. Only HTTPS (port 443) is open. Its web UI is
JavaScript-only and needs a login, so no command-line read access is available today.

```sh
curl -sk https://192.168.252.5/            # login page
```

The UI talks to CGI endpoints under `/cgi/get.cgi?cmd=...` and `/cgi/set.cgi?cmd=...`
(for example `vlan_vlanList`, `vlan_vlanPvid`, `port_portInfo`). These need a logged-in
session cookie. The login credentials are not recorded here.

## `oams` — this laptop

`oams` is the local host. Run commands directly. Its NIC is `enp4s0`. The VLAN interfaces
are `pic@enp4s0`, `mgmt@enp4s0` and `drek@enp4s0`, managed by NetworkManager profiles
`vlan-pic`, `vlan-mgmt` and `vlan-drek`.
