# The `development/llm/omp` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It registers the OhMyPi (`omp`) coding agent as an application entry, so the `apps` aspect
# installs it and keeps its data directory across a wipe.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **One class only.** The old module holds a Home Manager half and a forward half. den needs no
#    forward: a consumer names the class it wants.
# 3. **The `apps` aspect comes in through `includes`.** It declares `kdn.apps`, and den collapses a
#    diamond, so several aspects may name it.
# 4. **The package becomes an option, and it may be absent.** `pkgs.omp` comes from a separate flake
#    overlay, not from nixpkgs. A consumer without that overlay has no `pkgs.omp`, so the default
#    falls back to `null` and the aspect then registers nothing. The old module reads `pkgs.omp`
#    straight, so it throws for such a consumer.
#
# The `enable` inside `kdn.apps.<name>` is an option of the `apps` submodule, not an option of this
# aspect. A submodule `enable` is allowed.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.dev-llm-omp.includes = [ kdn.apps ];

  kdn.dev-llm-omp.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.kdn.dev-llm-omp.package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.omp or null;
        defaultText = lib.literalExpression "pkgs.omp or null";
        description = ''
          The `omp` package this aspect registers.

          `pkgs.omp` comes from the `can1357/oh-my-pi` flake overlay, not from nixpkgs. With no
          overlay the default is `null` and this aspect registers no application.
        '';
      };

      config = lib.mkIf (config.kdn.dev-llm-omp.package != null) {
        kdn.apps.omp.enable = true;
        kdn.apps.omp.package.original = config.kdn.dev-llm-omp.package;
        # `omp` keeps its configuration and its sessions in `~/.omp`.
        kdn.apps.omp.dirs.data = [ "/.omp" ];
      };
    };
}
