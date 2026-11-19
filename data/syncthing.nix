# The Syncthing topology for the `kdn` synced shares.
#
# One share is one Syncthing folder under `~/.local/share/kdn/synced/<share>` on every host that
# holds it. The device IDs come from `stc id` on each host; a host is listed in `shares` only when
# it holds that share.
#
# `large` is deliberately absent from etra: the router keeps the small state, not the bulk data.
# The pre-existing `~/dev` folder is not part of this set; the declarative settings are additive
# (`overrideFolders = false`), so `~/dev` and its device pairing stay untouched.
{
  devices = {
    oams = "3L5US77-RUQ4V73-BJ2ETE3-RBLVZBS-55JPSFL-I6D2WF2-3Z4KPX5-XX5PKAD";
    brys = "LFK67FC-57LG7TR-5WQULWG-32R6PQ7-3HMHFIB-DORO4WT-L6PTIYE-C5GWNAI";
    etra = "QSMJQOZ-PKLRCZ4-SYONVHB-YIV2RDN-R23KMQO-TAH4MED-WJ2EQJE-GSICUAX";
  };

  shares = {
    secret-stores = [
      "oams"
      "brys"
      "etra"
    ];
    small = [
      "oams"
      "brys"
      "etra"
    ];
    medium = [
      "oams"
      "brys"
      "etra"
    ];
    large = [
      "oams"
      "brys"
    ];
  };
}
