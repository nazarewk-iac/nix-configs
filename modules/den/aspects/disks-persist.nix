# The user half of impermanence, as a den aspect.
#
# ## What it does
#
# It declares `kdn.disks.persist` in a Home Manager scope, and it wires the read-only
# `kdn.apps-persist` output of ../aspects/apps.nix into that option. The host reads the result back
# through `config.home-manager.users.<name>.kdn.disks.persist`, which is what ../aspects/disks.nix
# does.
#
# ## Why a separate aspect
#
# den partitions an aspect by scope. `disks` is a host aspect, so it cannot declare a user option.
# The old tree used `home-manager.sharedModules` for this, and den has no route for that. So the
# user half becomes its own aspect, and a host includes both.
#
# A user who wants a path of their own needs this aspect too, because it carries the option
# declaration into the user scope:
#
#     kdn.disks.persist."usr/config".directories = [ ".config/my-app" ];
#
# ## The one-line wire that ../aspects/apps.nix asks for
#
# `apps.nix` publishes `kdn.apps-persist.directories` and `kdn.apps-persist.files`, both read-only
# and both grouped by bucket. Its header names the exact wire, and the `config` block below is that
# wire.
#
# The read uses `config.kdn.apps-persist or { }`. So this aspect works with `apps` and without it.
#
# **One aspect reads another aspect's option here.** The layer-C port permits this pattern: a read
# through `config.kdn.<other> or { }`. The standalone rule forbids a read of the two old trees only,
# and it says nothing about a sibling aspect. The alternative is a host-side wire, which repeats one
# line per host and buys no isolation.
#
# **That decision is provisional.** Revise this file when the owner decides otherwise.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.disks-persist.homeManager =
    {
      config,
      lib,
      ...
    }:
    let
      # The read-only output of ../aspects/apps.nix, or an empty set when that aspect is absent.
      appsPersist = config.kdn.apps-persist or { };
      directories = appsPersist.directories or { };
      files = appsPersist.files or { };

      # Every bucket either side names. `apps` fills six of them, and a user may name one more.
      buckets = lib.unique (builtins.attrNames directories ++ builtins.attrNames files);
    in
    {
      imports = [
        ../common/persist.nix
      ];

      config.kdn.disks.persist = lib.genAttrs buckets (bucket: {
        directories = directories.${bucket} or [ ];
        files = files.${bucket} or [ ];
      });
    };
}
