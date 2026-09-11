# The `development/web` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It adds the HTML, CSS and JSON language servers to Helix, and it pulls in the Node.js aspect.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The `enable` write becomes an `includes` entry.** The old module writes
#    `kdn.development.nodejs.enable`, in both halves, as `lib.mkDefault true`. den collapses a
#    diamond, so several aspects may name the same one.
# 3. **One class only.** After the `enable` write moves to `includes`, the NixOS half holds a forward
#    and nothing else. den needs no forward.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `pkgs` only.
{ kdn, ... }:
{
  kdn.dev-web.includes = [ kdn.dev-nodejs ];

  kdn.dev-web.homeManager =
    { pkgs, ... }:
    {
      programs.helix.extraPackages = with pkgs; [ vscode-langservers-extracted ];
    };
}
