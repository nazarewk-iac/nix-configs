# The remote desktop server, as a den aspect. It ports `desktop/remote-server` of the old tree.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does today: nothing, unless you opt in
#
# The old module holds one service line, and that line is commented out. So the old module is a
# placeholder, and this aspect keeps the same effect. `kdn.desktop-remote-server.teamviewer` carries
# the switch, and it is `false` by default.
#
# The reason for the comment, copied from the old module:
#
# > 2026-09-09: put teamviewer back when the fetch works again. `pkgs.teamviewer` is a fixed-output
# > derivation over a vendor `.deb` file. It is unfree, so Hydra never builds it and no substituter
# > holds the output. The fetch is the only source, and the network resolves the vendor host to a
# > DNS-filter block address that answers HTTP 403 for the whole domain. nixpkgs is correct: master
# > pins the same version and the same hash, and the vendor still serves the file with HTTP 200
# > through a public resolver. So there is nothing to fix upstream. Two real fixes, both outside this
# > repository: allow the vendor domain in the network's DNS policy, or give the Nix builder a public
# > resolver for that one fetch.
#
# ## Why the switch is an option, and why it stays off
#
# A den check forces every aspect and every class with an empty consumer. A `true` default would put
# an unfree fixed-output derivation into that force pass, and the check would then fail on the same
# blocked fetch. So the option holds the opinion, and no check turns it on.
#
# ## Class list: `nixos`
#
# `services.teamviewer` is a NixOS option. So this aspect holds one target.
#
# It sets no `kdn.graphical`. A remote desktop server can run with a virtual display only, and this
# aspect configures nothing today. The desktop aspect that a host also includes states the flag.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The option below names the program, not a
#    state, so it stays a plain opinion.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
let
  nixosTarget =
    { config, lib, ... }:
    let
      cfg = config.kdn.desktop-remote-server;
    in
    {
      options.kdn.desktop-remote-server.teamviewer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Run the TeamViewer daemon.

          It stays off by default, because the package is unfree and its only source is a vendor
          fetch that a DNS filter can block. See the header of this file.
        '';
      };

      config = lib.mkIf cfg.teamviewer {
        services.teamviewer.enable = true;
      };
    };
in
{
  kdn.desktop-remote-server.nixos = nixosTarget;
}
