---
type: Reference
description: VLAN list and physical link map of the home network (etra, coll, talt, quip and the hosts behind them).
timestamp: 2026-09-28T21:45:00+02:00
authored_by: agent
---

# Network topology

This file records the VLANs and the physical links of the home network. It reflects the live
state on 2026-09-28. The devices are:

| Device   | Role                     | Model                    | Management address                       |
|----------|--------------------------|--------------------------|------------------------------------------|
| `etra`   | Router and DHCP server   | NixOS host               | 192.168.73.1, 192.168.252.1, 10.92.0.1   |
| `coll`   | Core switch              | TP-Link SG3428X-M2       | 192.168.73.207, 192.168.252.11           |
| `talt`   | Access switch            | MikroTik CRS312-4C+8XG   | 192.168.73.95, 192.168.88.1              |
| `quip`   | Access switch            | Zyxel XGS1250-12         | 192.168.252.5                            |
| `oams`   | Laptop (this host)       | —                        | 192.168.73.49, 192.168.252.33            |

## VLANs

| VLAN   | Name                  | Purpose                 | IPv4 subnet        | Gateway                  | Status       |
|--------|-----------------------|-------------------------|--------------------|--------------------------|--------------|
| 1      | System-VLAN (`lan`)   | Primary LAN             | 192.168.73.0/24    | 192.168.73.1 (`etra`)    | Active       |
| 946    | `mgmt`                | Management              | 192.168.252.0/24   | 192.168.252.1 (`etra`)   | Active       |
| 1342   | `yelk-lan`            | `yelk` host network     | unknown            | unknown                  | Unverified   |
| 1859   | `pic-vlan`            | `pic` cluster network   | 10.92.0.0/24       | 10.92.0.1 (`etra`)       | Active       |
| 2199   | `etra-lan`            | Unused                  | none               | none                     | Vestigial    |
| 3547   | `drek-lan`            | `drek` network          | 192.168.41.0/24    | 192.168.41.1 (`drek`)    | Active       |

Notes:

- VLAN 1 is untagged on the access ports. `etra` holds 192.168.73.1/24 on it.
- VLAN 946 is tagged on every inter-switch link. It carries switch management.
- VLAN 2199 has no address and no untagged member on any device. It is probably a leftover.
- VLAN 1342 is tagged on `coll` and `talt`, but no host answers on it today. The old `yelk`
  access port (`talt ether6`) is disabled.

### VLAN membership per device

`U` = untagged member, `T` = tagged member, `—` = no member.

| Device   | 1   | 946   | 1342   | 1859   | 2199   | 3547   |
|----------|-----|-------|--------|--------|--------|--------|
| `etra`   | U   | T     | —      | T      | —      | —      |
| `coll`   | U   | T     | T      | T      | T      | T      |
| `talt`   | U   | T     | T      | T      | T      | T      |
| `quip`   | U   | T     | —      | —      | —      | —      |

Membership details:

- `etra`: `lan` carries VLAN 1 untagged; `mgmt` and `pic` are tagged sub-interfaces of `lan`.
- `coll`: VLAN 1 is untagged on every port. VLANs 946, 1342, 1859, 2199 and 3547 are tagged
  on Po1, Po2, Po3, Po4, Po5 and Tw1/0/23-24 (946 is not on Po2-Po4).
- `talt`: VLAN 1 is untagged on `ether1`, `ether3`, `ether4`, `ether5` and `bond-coll`.
  VLAN 946, 1342, 2199 and 3547 are tagged on every active port. VLAN 1859 is tagged on
  `ether1`, `ether4`, `ether5` and `bond-coll`.
- `quip`: VLAN 1 is untagged on port 8 and port 11. VLAN 946 is tagged on port 11.

## Physical links

| Endpoint A   | Port A                             | Endpoint B               | Port B                          | Medium   | Speed       | Notes                     |
|--------------|------------------------------------|--------------------------|---------------------------------|----------|-------------|---------------------------|
| `etra`       | `enp2s0` + `enp3s0` (bond `lan`)   | `coll`                   | Po5 = Tw1/0/23 + Tw1/0/24       | Copper   | 2.5G each   | 802.3ad LACP              |
| `coll`       | Po1 = Te1/0/27 + Te1/0/28          | `talt`                   | `bond-coll` = combo3 + combo4   | Fiber    | 10G         | 802.3ad LACP              |
| `talt`       | `ether1`                           | `quip`                   | port 11                         | Copper   | 10G         | Uplink                    |
| `quip`       | port 8                             | `oams`                   | `enp4s0`                        | Copper   | 1G          | This host                 |
| `talt`       | `ether2`                           | `drek`                   | —                               | Copper   | —           | Tagged only, PVID 3547    |
| `talt`       | `ether3`                           | `anji`                   | —                               | Copper   | —           | VLAN 1 untagged           |
| `talt`       | `ether4`                           | `brys`                   | —                               | Copper   | —           | VLAN 1 untagged           |
| `talt`       | `ether5`                           | `moak` and other hosts   | —                               | Copper   | —           | VLAN 1 untagged           |
| `talt`       | `ether9`                           | management network       | —                               | Copper   | —           | `br-mgmt`, 192.168.88.1   |
| `coll`       | Po2 = Tw1/0/11-14                  | `pwet`                   | —                               | Copper   | down        | `pic` cluster host        |
| `coll`       | Po3 = Tw1/0/15-18                  | `turo`                   | —                               | Copper   | down        | `pic` cluster host        |
| `coll`       | Po4 = Tw1/0/19-22                  | `yost`                   | —                               | Copper   | down        | `pic` cluster host        |
| `coll`       | Tw1/0/9                            | unknown                  | —                               | Copper   | 1G          | Unidentified              |

Notes:

- The `coll`–`talt` LAG runs on one active member. `coll` Te1/0/27 and `talt` `combo3` carry
  traffic. `coll` Te1/0/28 is hot-standby, and `talt` `combo4` has no link.
- `coll` Tw1/0/9 is up at 1G, but it has no LLDP neighbor and no learned MAC.

### `quip` port map

| Port    | Connection        | PVID      | Notes                                                         |
|---------|-------------------|-----------|---------------------------------------------------------------|
| 8       | `oams` `enp4s0`   | 1         | This host                                                     |
| 11      | `talt` `ether1`   | 1         | Uplink, VLAN 946 tagged; PVID changed 946 → 1 on 2026-09-28   |
| other   | unknown           | unknown   | Not read from the device                                      |

## Path from `oams` to `etra`

`oams` `enp4s0` → `quip` port 8 → `quip` port 11 → `talt` `ether1` → `talt` `bond-coll` →
`coll` Po1 → `coll` Po5 → `etra` `lan` bond.

## Known gaps

- The `quip` port table is incomplete. The device UI is JavaScript-only and offers no read
  access without a login.
- VLAN 1342 and VLAN 2199 have no confirmed purpose or subnet.
- The host `kvm-2795` (MAC `48:da:35:6f:27:95`) does not appear in any switch MAC table, in
  the `etra` ARP table, or in the `etra` DHCP leases. Two other KVMs do appear:
  `kvm-050c` (`48:da:35:6f:05:0c`, 192.168.73.132) and `kvm-26e2` (`48:da:35:6f:26:e2`,
  192.168.73.52), both on `talt ether5`.
