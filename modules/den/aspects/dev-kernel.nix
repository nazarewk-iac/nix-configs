# The `development/kernel` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs everything the Linux kernel needs to build, from the kernel's own requirements page:
# https://www.kernel.org/doc/html/v5.6/process/changes.html. It also adds the build inputs of the
# kernel the host runs.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **One class only.** Every package here is Linux-only, and the old module already guards them
#    with `ifTypes [ "nixos" ]`.
# 3. **`kdn.env.packages` goes.** The target writes `environment.systemPackages`. Design B.
# 4. **The `kdn.toolset.unix.enable` write goes.** It belongs to another area. A consumer that wants
#    the Unix tool set names that aspect too.
# 5. **The comment above `libelf` loses a checkout path.** The old comment holds a full compiler
#    error from one machine, with a personal home directory in it. The fact is the same without it.
# 6. **`reiserfsprogs` goes.** nixpkgs removed the attribute, and it now throws. A throw defeats
#    ../common/filter-packages.nix, so the old module cannot evaluate at all with the pinned nixpkgs.
#    See the comment at the package list.
# 7. **`pcmciaUtils` becomes `pcmciautils`.** nixpkgs renamed it, and the old name prints a
#    deprecation warning on every evaluation. The package is the same one.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-kernel.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # See https://www.kernel.org/doc/html/v5.6/process/changes.html
      environment.systemPackages = import ../common/filter-packages.nix { inherit lib; } (
        # the current minimal requirements
        (with pkgs; [
          gcc
          gnumake
          binutils
          flex
          bison
          kmod
          e2fsprogs
          jfsutils
          # `reiserfsprogs` is gone from nixpkgs since 2025-11-13, because ReiserFS has no
          # maintenance upstream. The attribute now throws, and a throw defeats
          # ../common/filter-packages.nix: the first predicate reads `p.meta.broken`, and `or` guards
          # a missing attribute, not a throw. So the name must go.
          xfsprogs
          squashfs-tools-ng
          btrfs-progs
          pcmciautils # nixpkgs renamed `pcmciaUtils` to this name
          unixtools.quota
          ppp
          nfs-utils
          procps
          oprofile
          eudev # udev
          grub2
          mcelog
          iptables
          openssl
          bc
          sphinx
        ])
        # the kernel compilation itself
        ++ (with pkgs; [
          gcc
          gnumake
          binutils
          pkg-config
          flex
          bison
          perl
          bc
          openssl
        ])
        # `objtool` includes `gelf.h`, which comes from libelf and elfutils
        ++ (with pkgs; [
          libelf
          elfutils
        ])
        ++ config.boot.kernelPackages.kernel.nativeBuildInputs
        ++ config.boot.kernelPackages.kernel.depsBuildBuild
      );
    };
}
