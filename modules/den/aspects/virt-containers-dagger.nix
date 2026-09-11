# The Dagger pipeline tooling, as a den aspect. It ports
# `modules/universal/virtualisation/containers/dagger/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the CUE command and the CUE language server, plus the Dagger command when the consumer
# names a package for it.
#
# ## nixpkgs ships no `dagger` attribute — a second latent defect
#
# The old module writes `pkgs.dagger`. nixpkgs holds no such attribute, so that line raises
# "undefined variable 'dagger'". Nix laziness hides the failure today: no host turns this module on,
# so nothing forces the list. A den aspect that forces every value makes the failure real. Measured
# on 2026-09-11, on both `x86_64-linux` and `aarch64-darwin`.
#
# So the `package` option below defaults to `pkgs.dagger or null`, and the target adds the package
# only when the attribute exists. A consumer that wants Dagger today names its own package:
#
#     kdn.virtualisation.containers.dagger.package = inputs.dagger.packages.<system>.dagger;
#
# The old module keeps its own line. This file touches no `modules/universal/` file.
#
# ## Three classes, one body
#
# The old module writes `kdn.env.packages`, so every context gets the same list. Design B drops that
# option, so each target writes the native option of its own class. The `let` below builds one target
# module, and a flag picks the option. The three classes are separate module systems, so the
# duplicate option declaration is safe.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** Each target writes its own native option. Design B.
# 3. **The Dagger package becomes an option.** See above.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  mkTarget =
    { home }:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.virtualisation.containers.dagger;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      packages = filterPackages (
        (with pkgs; [
          cue
          cuelsp
        ])
        ++ lib.optional (cfg.package != null) cfg.package
      );
    in
    {
      options.kdn.virtualisation.containers.dagger.package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.dagger or null;
        defaultText = lib.literalExpression "pkgs.dagger or null";
        description = ''
          The Dagger command. `null` installs no such command.

          nixpkgs holds no `dagger` attribute, so the default is `null` today. A consumer that wants
          Dagger names a package from its own flake input.
        '';
      };

      config = if home then { home.packages = packages; } else { environment.systemPackages = packages; };
    };
in
{
  kdn.virt-containers-dagger.nixos = mkTarget { home = false; };

  kdn.virt-containers-dagger.darwin = mkTarget { home = false; };

  kdn.virt-containers-dagger.homeManager = mkTarget { home = true; };
}
