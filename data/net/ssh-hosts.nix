# The hosts this fleet owns, as ssh `Host` patterns. One definition, two consumers:
#
#   * `kdn.ssh-access.identityAgentPatterns` — which addresses use the hardware agent
#     instead of whatever agent the desktop provides;
#   * `kdn.ssh-ca.certificatePatterns` — which hosts are offered the CA user
#     certificate.
#
# A destination missing from this list gets neither the agent nor a certificate, so a
# new zone belongs here, next to the LAN ranges.
{
  patterns = [
    "*.kdn.im"
    "*.nb.net.int.kdn.im" # NetBird FQDNs, e.g. brys.priv.nb.net.int.kdn.im
    "*.netbird.cloud" # short NetBird names
    "192.168.41.*" # drek lan
    "192.168.73.*" # etra lan
    "192.168.252.*" # etra mgmt
  ];
}
