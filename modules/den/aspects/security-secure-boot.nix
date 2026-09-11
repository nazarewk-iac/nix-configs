# The `security/secure-boot` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It replaces the systemd-boot loader with lanzaboote, so the machine boots a signed kernel. It
# also brings the disk-encryption command set, because `sbctl` enrolls the keys.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The `kdn.toolset.fs.encryption.enable` write becomes an `includes` entry.** den collapses
#    the diamond, so `security-disk-encryption` may name the same aspect and it loads once.
# 3. **The aspect imports the lanzaboote module itself.** The old tree imports it for every host,
#    even a host that boots with GRUB. An aspect carries its own flake-input module instead.
#    Precedent: ./disks.nix:206-207.
# 4. **The PKI bundle path becomes an option.** The old module hard-codes `/etc/secureboot`. The
#    default keeps that path, so behaviour does not change, and an adopter with another layout
#    states a path of its own.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `pkiBundle` is the one option, and it is a
#    path, not a flag.
# 3. **No custom module argument.** The target module takes `config` and `lib` only. `inputs` comes
#    from this file's own scope, because the check harness passes `pkgs` alone to a target.
{ kdn, inputs, ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.security.secure-boot.pkiBundle = lib.mkOption {
        type = lib.types.path;
        default = "/etc/secureboot";
        example = "/var/lib/secureboot";
        description = ''
          Where the Secure Boot keys live. lanzaboote signs with the keys under this directory, and
          `sbctl` enrolls them.

          The old module hard-codes `/etc/secureboot`, and this default keeps that path.
        '';
      };
    };

  nixosTarget =
    { config, lib, ... }:
    {
      imports = [
        declaration
        inputs.lanzaboote.nixosModules.lanzaboote
      ];

      # lanzaboote replaces the systemd-boot module. An installer-generated configuration turns
      # systemd-boot on, so this line forces it off.
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.lanzaboote.enable = true;
      boot.lanzaboote.pkiBundle = config.kdn.security.secure-boot.pkiBundle;
    };
in
{
  kdn.security-secure-boot.includes = [ kdn.toolset-fs-encryption ];

  kdn.security-secure-boot.nixos = nixosTarget;
}
