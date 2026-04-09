# How to set up OpenVPN?

1. prepare secrets directory: `sudo kdn-openvpn-setup kdn-aws.ovpn kdn-aws.p12`
2. add an instance: `kdn.networking.openvpn.instances.goggles-humongous = { };`