# `kdn.programs.dconf`, as a den aspect. It ports `modules/universal/programs/dconf/default.nix`.
#
# The old module declares `enable` with `default = false`, and that is a reachable `enable` option.
# It disappears here: inclusion of the aspect is the switch.
{ kdn, ... }:
{
  kdn.program-dconf.includes = [ kdn.apps ];

  kdn.program-dconf.nixos.programs.dconf.enable = true;

  kdn.program-dconf.homeManager = {
    dconf.enable = true;

    kdn.apps.dconf = {
      enable = true;
      # dconf ships inside the desktop stack, so the aspect installs no package of its own.
      package.install = false;
      dirs.config = [ "dconf" ];
    };
  };
}
