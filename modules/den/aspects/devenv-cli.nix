# The `devenv` install slot, as a den aspect. It ports `modules/slots/devenv/default.nix`.
#
# The slot stays in place and keeps working. This aspect is the parallel den implementation.
#
# ## Why this slot
#
# It is the **widest** slot in the repository. No slot targets all four kinds, and this one is the
# only slot that targets three: `nixos`, `darwin` and `home`. So it is the smallest real port that
# exercises every den class the test harness needs.
#
# The `devenv` target is **new**. The slot has none, because the slot installs the CLI for an
# interactive login shell. A devenv shell wants it for a second reason: a nested devenv shell, and
# a CI job whose entry point is the shell itself.
#
# ## The name
#
# `devenv-cli`, not `devenv`. `devenv` is already a den **class** in this tree
# (`../classes/devenv.nix`), and `den.devenv.*` is already an option prefix. An aspect named
# `devenv` would read as one of those at every call site.
#
# ## Two limits this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence. Condition 2 of the 004 spike. Each target below is a
#    plain module function, so it takes `pkgs` and `lib` and no entity.
# 2. **No `enable` option.** Inclusion is the switch. A second declaration of `kdn.devenv.enable`
#    would also collide with the slot inside one module set.
{ ... }:
let
  # `nixos` and `darwin` take one identical module. Both option paths exist in both class trees:
  # nix-darwin declares `nix.extraOptions` at `modules/nix/default.nix:543`.
  #
  # `keep-outputs` and `keep-derivations` stop the nix garbage collector from removing a devenv
  # build output or derivation. devenv holds its GC roots through them.
  systemModule =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.devenv ];
      nix.extraOptions = ''
        keep-outputs = true
        keep-derivations = true
      '';
    };
in
{
  kdn.devenv-cli.nixos = systemModule;
  kdn.devenv-cli.darwin = systemModule;

  # den names this class `homeManager`. The slot's target is `home`. The two mean the same thing.
  #
  # The aspect enables **no** shell. It fills in the hook for each shell that the consumer enables,
  # and home-manager writes an `initExtra` only for an enabled shell. A slot must not turn a user's
  # login shell on.
  kdn.devenv-cli.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = [ pkgs.devenv ];

      programs.bash.initExtra = ''
        eval "$(${lib.getExe pkgs.devenv} hook bash)"
      '';
      programs.zsh.initContent = ''
        eval "$(${lib.getExe pkgs.devenv} hook zsh)"
      '';
      programs.fish.interactiveShellInit = ''
        ${lib.getExe pkgs.devenv} hook fish | source
      '';
    };

  # The new target. The slot has none — see the header.
  kdn.devenv-cli.devenv =
    { pkgs, ... }:
    {
      packages = [ pkgs.devenv ];

      # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
      #
      # devenv puts this in `config.enterTest`, and `config.test` wraps it as a script. It runs
      # under `devenv test` and under `checks.<system>.den-smoke-*`. It does **not** run on shell
      # entry (`enterShell`), and it never runs during a nix-darwin or a NixOS activation.
      #
      # Every assertion stays offline. The check runs in a build sandbox with no network and no real
      # `$HOME`. `devenv --version` is safe: measured under `env -i` on 2026-09-10, it prints the
      # version and exits 0 with no network call. A bare `devenv version` subcommand is **not**
      # safe — it reads the project, and the sandbox has none.
      enterTest = ''
        echo "• devenv-cli: the binary reports a version" >&2
        devenv --version | grep -qE '^devenv [0-9]+\.'

        echo "• devenv-cli: --help exits 0" >&2
        devenv --help >/dev/null

        echo "• devenv-cli: the hook subcommand emits shell code for each shell" >&2
        for shell in bash zsh fish; do
          devenv hook "$shell" | grep -q . || {
            echo "devenv hook $shell produced nothing" >&2
            exit 1
          }
        done
      '';
    };
}
