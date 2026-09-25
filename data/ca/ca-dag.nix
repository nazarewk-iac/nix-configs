# The KDN certificate-authority graph, as data.
#
# One node is declared here, so the four universal hosts share one source of truth and cannot
# drift. The node is the fresh managed root CA that decision D-B introduces. It is separate from
# the old "KDN LLM CA": `data/ca/ca.pub` and `data/ca/ca.key.sops` stay untouched.
#
# The `kdn-certs` CLI reads this node and creates it: `kdn-certs ca init` generates the key,
# creates the self-signed root, writes `data/ca/kdn.crt`, and SOPS-encrypts the key to
# `data/ca/kdn.key.sops`. The key is encrypted to the two unattended YubiKey identities only, so
# `ca init` needs no touch and no PIN. See the `.sops.yaml` rule `data/ca/kdn\.key\.sops$`.
#
# `ssh = true` because design § 7 needs an SSH CA, and the `kdn.ssh-ca` aspect is already built.
#
# This file is a plain module. It declares no option and emits no configuration of its own; it
# only sets the CA node. A host imports it next to the `ca-dag` and `certificates` aspects.
{
  kdn.ca-dag.cas.kdn = {
    type = "root";
    commonName = "KDN certificates root CA";
    directory = "data/ca";
    certFile = "kdn.crt";
    keyFile = "kdn.key";
    keySource = "managed";
    ssh = true;
  };
}
