# The `profile/machine/dev` module of the old tree, as one den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# `profile-dev` is the bundle for a development machine. It names 17 language and cloud aspects,
# the terminal IDE and the container runtime.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module carries **no** content of its own: `dev/default.nix:52-53` writes
# `kdn.env.packages = with pkgs; [ ];`, an empty list. A pure-`includes` aspect reports
# `classes = [ ]` (`modules/den/lib.nix:246-265`), exports no pair, and gets zero check coverage in
# silence. So the one real fact the old module computes becomes this aspect's own content.
#
# `dev/default.nix:55-57` writes:
#
#     kdn.toolset.mikrotik.enable = lib.mkDefault (
#       pkgs.stdenv.hostPlatform.isx86 && config.kdn.desktop.enable
#     );
#
# An aspect writes no option of another aspect, and an `includes` entry is unconditional. So this
# aspect **publishes** the same test as a read-only option, and the consumer wires it:
#
#     kdn.toolset-mikrotik ... named in the host's own `includes`, when
#     config.kdn.profile-dev.mikrotikTools is true
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The 20 `enable` writes become `includes` entries.**
# 3. **`languages.enable`, `containers.enable` and `desktop.enable` go.** Each one is a reachable
#    `enable`, and rule 2 forbids that. A consumer drops the aspects it does not want, one name at
#    a time — that is finer control than the three old switches gave.
# 4. **`kdn.development.cloud.azure` goes.** The old value is `lib.mkDefault false`, so the aspect
#    was off. An `includes` entry would turn it on.
# 5. **`kdn.toolset.ide.enable` becomes `program-terminal-ide`.** The old `toolset/ide` module is a
#    pure forwarder. Its second write, `kdn.development.jetbrains.enable`, is desktop-gated, so
#    `dev-jetbrains` goes to `profile-workstation` instead — the one bundle that is both a desktop
#    and a development machine.
# 6. **`kdn.profile.machine.desktop.enable` goes.** See the plan's `## Not planned, and why`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.** See change 3. `mikrotikTools` is read-only and it is not
#    named `enable`.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  declaration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ ../common/graphical.nix ];

      options.kdn.profile-dev.mikrotikTools = lib.mkOption {
        readOnly = true;
        type = lib.types.bool;
        default = pkgs.stdenv.hostPlatform.isx86 && config.kdn.graphical;
        defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isx86 && config.kdn.graphical";
        description = ''
          Whether this machine wants the MikroTik tools. It is read-only.

          The old module writes this test straight into `kdn.toolset.mikrotik.enable`, which another
          aspect declares. An aspect writes no option of another aspect, and an `includes` entry is
          unconditional. So the consumer reads this value and names `kdn.toolset-mikrotik` in its
          own `includes` when the value is true.

          The tools are x86-only, and the old module also required a desktop.
        '';
      };
    };
in
{
  kdn.profile-dev.includes = [
    kdn.dev-ansible
    kdn.dev-cloud
    kdn.dev-cloud-aws
    kdn.dev-data
    kdn.dev-db
    kdn.dev-documents
    kdn.dev-elixir
    kdn.dev-golang
    kdn.dev-java
    kdn.dev-k8s
    kdn.dev-nickel
    kdn.dev-nix
    kdn.dev-python
    kdn.dev-rpi
    kdn.dev-rust
    kdn.dev-terraform
    kdn.dev-web
    kdn.program-terminal-ide
    kdn.virt-containers
    kdn.virt-containers-podman
  ];

  kdn.profile-dev.nixos = declaration;
  kdn.profile-dev.darwin = declaration;
  kdn.profile-dev.homeManager = declaration;
}
