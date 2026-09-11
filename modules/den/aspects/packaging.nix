# The language-version manager, as a den aspect. It ports the whole `packaging` area of the old
# tree.
#
# Old path:
# modules/universal/packaging/
#
# The old tree keeps every byte. This file is the parallel den implementation.
#
# ## One aspect
#
# The area holds one module, `packaging/asdf`. So the file holds one aspect, `packaging-asdf`, and
# it serves three classes: `nixos`, `darwin` and `homeManager`. The old module writes the package
# with no guard, and it adds a shell hook per context.
#
# ## What the port changes
#
# 1. **`kdn.env.packages` does not survive.** Design B: each target writes the native option of its
#    own class.
# 2. **`kdn.toolset.essentials.enable` becomes an `includes` edge.** The old module turns that group
#    on for coreutils. den has no `enable`, so the aspect includes `toolset-essentials` instead.
# 3. **The `enable` option is gone.** Inclusion is the switch. The `package` option stays, and it
#    keeps `pkgs.asdf-vm` as its default.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Every target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  # One option, shared by the three class trees. Each target imports it, so each class declares it
  # exactly once.
  asdfOptions =
    { lib, pkgs, ... }:
    {
      options.kdn.packaging.asdf.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.asdf-vm;
        defaultText = lib.literalExpression "pkgs.asdf-vm";
        description = "The asdf version manager this consumer installs.";
      };
    };
in
{
  kdn.packaging-asdf.includes = [ kdn.toolset-essentials ];

  kdn.packaging-asdf.nixos =
    { config, ... }:
    {
      imports = [ asdfOptions ];

      environment.systemPackages = [ config.kdn.packaging.asdf.package ];

      environment.interactiveShellInit = ''
        [[ -z "$HOME" ]] || export PATH="$HOME/.asdf/shims:$PATH"
      '';
    };

  kdn.packaging-asdf.darwin =
    { config, ... }:
    {
      imports = [ asdfOptions ];

      environment.systemPackages = [ config.kdn.packaging.asdf.package ];
    };

  kdn.packaging-asdf.homeManager =
    { config, lib, ... }:
    {
      imports = [ asdfOptions ];

      home.packages = [ config.kdn.packaging.asdf.package ];

      programs.fish.interactiveShellInit = ''
        fish_add_path --prepend --move "$HOME/.asdf/shims"
      '';

      home.activation.asdfReshim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -d "$HOME/.asdf/shims" ] ; then
          $DRY_RUN_CMD rm -rf "$HOME/.asdf/shims"
        fi
        $DRY_RUN_CMD "${config.kdn.packaging.asdf.package}/bin/asdf" reshim
      '';
    };
}
