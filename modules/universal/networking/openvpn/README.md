---
type: Playbook
description: Steps for setting up an OpenVPN instance with secrets and config.
timestamp: 2026-04-09T22:11:29+02:00
---

# How to set up OpenVPN?

1. prepare secrets directory: `sudo kdn-openvpn-setup kdn-aws.ovpn kdn-aws.p12`
2. add an instance: `kdn.networking.openvpn.instances.goggles-humongous = { };`