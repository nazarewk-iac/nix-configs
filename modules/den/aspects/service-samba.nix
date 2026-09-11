# SMB shares, as a den aspect. It ports `modules/universal/services/samba/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Samba with a read-only, non-browseable global block, it opens the SMB ports, and it turns
# on user shares. It names the machine in `server string` and in `netbios name`.
#
# ## The network data stays with the consumer
#
# The aspect names **no** network. The `hostsAllow` default names the loopback interface only, so a
# fresh consumer serves nobody until it states its own network. `hostsDeny` denies every route that
# `hostsAllow` does not name.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The Home Manager forward goes.** A den consumer includes the aspect where it wants it. The
#    old module forwards the whole option set into Home Manager, and that forward has no den
#    equivalent.
# 3. **The workgroup default becomes the Windows default.** The old default names this repository.
#    `WORKGROUP` is the name a fresh Windows network expects.
# 4. **The persist writes become output options.** See below.
#
# ## The persist directories become read-only outputs
#
# The old module writes two `kdn.disks.persist.*` buckets. An aspect must not write another aspect's
# option, so this aspect publishes two lists and the consumer wires them:
#
#     kdn.disks.persist."sys/data".directories = config.kdn.services.samba.persist.sysData;
#     kdn.disks.persist."usr/data".directories = config.kdn.services.samba.persist.usrData;
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.service-samba.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.services.samba;
    in
    {
      imports = [ ../common/host-name.nix ];

      options.kdn.services.samba.defaults.hostsAllow = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # The default names the loopback interface only. A consumer states its own network here.
        default = [
          "127.0.0.0/8"
          "localhost"
          "::1"
        ];
        description = ''
          The hosts that reach every share. The default names the loopback interface only, so a
          consumer that shares a file on a network states that network itself.
        '';
      };

      options.kdn.services.samba.defaults.hostsDeny = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "0.0.0.0/0"
          "::/0"
        ];
        description = "The hosts that reach no share. The default denies every other route.";
      };

      options.kdn.services.samba.defaults.workgroup = lib.mkOption {
        type = lib.types.str;
        default = "WORKGROUP";
        example = "HOME";
        description = "The SMB workgroup name. `WORKGROUP` is the Windows default.";
      };

      options.kdn.services.samba.persist.sysData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The directories this aspect wants on persistent system storage. The consumer wires the
          list into its own persistence option.
        '';
      };

      options.kdn.services.samba.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The directories this aspect wants on persistent user storage. The consumer wires the list
          into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          services.samba.enable = true;
          services.samba.openFirewall = true;
          services.samba.usershares.enable = true;
          services.samba.settings.global = {
            "workgroup" = cfg.defaults.workgroup;
            "server string" = "${config.kdn.hostName}-SMB";
            "netbios name" = config.kdn.hostName;
            "security" = "user";
            # note: localhost is the ipv6 localhost ::1
            "hosts allow" = builtins.concatStringsSep " " cfg.defaults.hostsAllow;
            "hosts deny" = builtins.concatStringsSep " " cfg.defaults.hostsDeny;
            "guest account" = "nobody";
            "map to guest" = "bad user";

            "create mask" = "0640";
            "directory mask" = "0751";
            "browseable" = "no";
            "writeable" = "no";
            "read only" = "yes";
          };
        }
        {
          kdn.services.samba.persist.sysData = [
            "/var/lib/samba"
          ];
          kdn.services.samba.persist.usrData = [
            (config.services.samba.settings.global."usershare path" or "/var/lib/samba/usershares")
          ];
        }
      ];
    };
}
