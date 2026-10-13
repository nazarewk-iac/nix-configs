# The brys SSH host certificate, shared by the main profile and every boot
# specialisation (see hosts/brys/llm-appliance.nix). Each brys boot then presents
# the host certificate and accepts CA user certificates, so `ssh brys` works by
# CA on any entry, not only the main one.
#
# The `ssh-ca` aspect pairs the certificate with its managed key. A client that
# trusts the KDN CA (`@cert-authority`) verifies the host by CA; an older client
# keeps its pinned key (OpenSSH `prefer_local_hostkeys`). The private key is a
# SOPS secret the `certificates` aspect decrypts to its runtime path.
{ kdnConfig, ... }:
{
  imports = [
    "${kdnConfig.self}/data/ca/ca-dag.nix"
  ]
  ++ kdnConfig.self.denLib.imports {
    class = "nixos";
    aspects = [
      "ca-dag"
      "certificates"
      "ssh-ca"
    ];
  };

  # The CA DAG and the leaf `certPath` resolve against this root.
  kdn.certificates.repoRoot = kdnConfig.self;

  # The SSH host certificate. `principals` names every form a client may connect
  # with, short name and each FQDN. OpenSSH does not strip a trailing dot before
  # it matches a principal, and the fleet's `kdn-ssh-access` addresses carry one,
  # so `kdn-certs` also signs the trailing-dot form of each FQDN at signing time.
  kdn.certificates.certs.ssh-host-brys = {
    ca = "kdn";
    type = "ssh-host";
    commonName = "brys";
    principals = [
      "brys"
      "brys.lan.etra.net.int.kdn.im"
      "brys.lan.drek.net.int.kdn.im"
      "brys.priv.nb.net.int.kdn.im"
      "brys.netbird.cloud"
    ];
    directory = "hosts/brys/certs";
    certFile = "ssh_host_ed25519-cert.pub";
    keyFile = "ssh_host_ed25519.key";
    keySource = "managed";
  };
}
