# The SSH identity of every host in the fleet, in one place.
#
# Three things used to be maintained by hand and drifted apart:
#
#   * the `principals` of each `ssh-host` certificate (one list per host config);
#   * the pins in `modules/universal/profile/machine/baseline/ssh_known_hosts`
#     (a hashed file, rewritten by hand);
#   * the patterns in `data/net/ssh-hosts.nix`-adjacent slot code.
#
# briv paid for the drift: its pin still named the installer key after the managed key took over,
# and every connection aborted with "REMOTE HOST IDENTIFICATION HAS CHANGED".
#
# `names` is the single source for the certificate principals. The first entry is the short name
# and must match the directory. `publicKeyFile` is the committed public half of the deployed key,
# the same one `kdnctl host ensure ssh-host-keys` writes to the host; the ssh-ca aspect turns the
# pair into a `known_hosts` entry, so a pin can no longer point at a key the host does not serve.
#
# This file is fleet data. `modules/den/aspects/ssh-hosts.nix` publishes it as `kdn.ssh-hosts`, and
# `kdn.ssh-ca` reads that option. A host missing from this file keeps whatever its own declaration
# says and gets no generated pin.
{
  anji = {
    names = [
      "anji"
      "anji.lan.etra.net.int.kdn.im"
      "anji.priv.nb.net.int.kdn.im"
      "anji.netbird.cloud"
    ];
    publicKeyFile = ../../hosts/anji/certs/ssh_host_ed25519_key.pub;
  };

  briv = {
    names = [
      "briv"
      "briv.lan.etra.net.int.kdn.im"
      "briv.priv.nb.net.int.kdn.im"
      "briv.netbird.cloud"
    ];
    publicKeyFile = ../../hosts/briv/certs/ssh_host_ed25519_key.pub;
  };

  brys = {
    names = [
      "brys"
      "brys.lan.etra.net.int.kdn.im"
      "brys.lan.drek.net.int.kdn.im"
      "brys.priv.nb.net.int.kdn.im"
      "brys.netbird.cloud"
    ];
    publicKeyFile = ../../hosts/brys/certs/ssh_host_ed25519_key.pub;
  };

  etra = {
    names = [
      "etra"
      "etra.lan.etra.net.int.kdn.im"
      "etra.lan.drek.net.int.kdn.im"
      "etra.priv.nb.net.int.kdn.im"
      "etra.netbird.cloud"
    ];
    publicKeyFile = ../../hosts/etra/certs/ssh_host_ed25519_key.pub;
  };

  moss = {
    names = [
      "moss"
      "moss.kdn.im"
      "moss.priv.nb.net.int.kdn.im"
      "moss.netbird.cloud"
    ];
    publicKeyFile = ../../hosts/moss/certs/ssh_host_ed25519_key.pub;
  };

  oams = {
    names = [
      "oams"
      "oams.lan.etra.net.int.kdn.im"
      "oams.lan.drek.net.int.kdn.im"
      "oams.priv.nb.net.int.kdn.im"
      "oams.netbird.cloud"
    ];
    publicKeyFile = ../../hosts/oams/certs/ssh_host_ed25519_key.pub;
  };
}
