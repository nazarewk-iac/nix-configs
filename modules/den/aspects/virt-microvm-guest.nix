# The `virtualisation/microvm/guest` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It makes the machine a microvm.nix guest. It turns `microvm.guest` on, shares the host's Nix store
# read-only over virtiofs, and keeps four things across a reboot: the journal, the machine id and
# the two SSH host keys. It also mounts one virtiofs share per preservation bucket, from
# `/var/lib/microvms-persist/<guest name>/<bucket>` on the host.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old default reads a guest feature flag, and den
#    has no feature set. A host that includes this aspect **is** a microvm guest.
# 2. **The old module also pins `microvm.guest.enable` to `false`.** It has to, because that option
#    defaults to `true`. This aspect imports the option module only when a host includes the
#    aspect, so the false branch goes.
# 3. **The `microvm-options` import becomes unconditional.** The old module imports it only for a
#    host that is *not* a guest, because the microvm.nix guest wrapper already carries the full
#    module. `nixosModules.microvm-options` and the wrapper's own import name the same file, and the
#    module system dedupes an import **by path**. So a real guest still loads it once. Measured
#    2026-09-11 against the locked microvm.nix revision.
# 4. **The `kdn.profile.machine.baseline.enable` write goes.** No `profile` aspect exists yet. A
#    guest that wants the baseline includes that aspect when a later batch lands it.
# 5. **The unused `microvmPersistNames` binding goes.** Nothing reads it.
#
# ## The state path
#
# `/var/lib/microvms-persist` is a path on the **host**. ./virt-microvm-host.nix holds the same
# literal, exactly as the two old modules do. The two aspects share no option, so a change needs an
# edit in both files.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence. The guest name comes from `kdn.hostName`, an option of
#    ../common/host-name.nix, not from an entity.
# 2. **No `enable` option.** Inclusion is the switch, and this aspect declares no option at all.
# 3. **No custom module argument.** The target module takes `config` and `lib` only. `inputs` comes
#    from this file's own scope, because the check harness passes `pkgs` alone to a target.
{ inputs, ... }:
let
  nixosTarget =
    { config, lib, ... }:
    {
      imports = [
        ../common/host-name.nix
        inputs.microvm.nixosModules.microvm-options
        inputs.preservation.nixosModules.preservation
      ];

      microvm.guest.enable = true;

      security.sudo.wheelNeedsPassword = lib.mkDefault false;

      preservation.enable = true;
      preservation.preserveAt."microvm".persistentStoragePath = "/nix/persist/microvm";
      preservation.preserveAt."microvm".directories = [
        {
          directory = "/var/log/journal";
          inInitrd = true;
        }
      ];
      preservation.preserveAt."microvm".files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
          how = "symlink";
          configureParent = true;
        }
        {
          file = "/etc/ssh/ssh_host_ed25519_key";
          how = "symlink";
          mode = "0600";
          inInitrd = true;
        }
        {
          file = "/etc/ssh/ssh_host_rsa_key";
          how = "symlink";
          mode = "0600";
          inInitrd = true;
        }
      ];

      microvm.shares = [
        {
          # the shared /nix/store
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }
      ]
      ++ lib.pipe config.preservation.preserveAt [
        (lib.attrsets.mapAttrsToList (
          persistName: preserveAtCfg: {
            source = "/var/lib/microvms-persist/${config.kdn.hostName}/${persistName}";
            mountPoint = preserveAtCfg.persistentStoragePath;
            tag = "microvm-persist-${persistName}";
            proto = "virtiofs";
          }
        ))
      ];
    };
in
{
  kdn.virt-microvm-guest.nixos = nixosTarget;
}
