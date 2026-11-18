# The `security/dynamic-netrc` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It rebuilds `/etc/nix/netrc` from the drop-in directory `/etc/nix/netrc.d/*.netrc` on every
# change. A sops template writes each credential as a drop-in, so no credential is ever written by
# hand and the assembled file is never persisted. It is a `systemd.path` unit plus a oneshot
# service, the same shape as `kdn.networking.dynamic-hosts` for `/etc/hosts`.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** The target writes `environment.systemPackages`, through
#    ../common/filter-packages.nix. Design B.
# 3. **The `kdn.managed.directories` write stays, with `managed` in `includes`.** The aspect owns
#    one directory and it includes the cleanup that reads the option. This is the `net-router`
#    shape: an aspect writes an included sibling's option at plain priority, and the sibling never
#    reads a name this file does not declare.
# 4. **The path is the same.** `/etc/nix/netrc.d` keeps its literal value, because a sops template
#    writes the drop-ins there and the old module's consumers name that path.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the aspect emits
# `nixos` only.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.security-dynamic-netrc.includes = [ kdn.managed ];

  kdn.security-dynamic-netrc.nixos =
    { lib, pkgs, ... }:
    let
      kdn-gen-netrc = pkgs.writeShellApplication {
        name = "kdn-gen-netrc";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
        ];
        text = ''
          mkdir -p /etc/nix/netrc.d
          tmp="$(mktemp /etc/nix/netrc.XXXXXX)"
          {
            find /etc/nix/netrc.d -name '*.netrc' \
              -exec printf '# START %s\n' {} \; \
              -exec cat {} \; \
              -exec printf '# END %s\n\n' {} \;
          } > "$tmp"
          chmod 0644 "$tmp"
          # `/etc/nix/netrc` is a bind mount from the persistence layer on a preserved host, so
          # a rename onto it fails with EBUSY. Copy through the mount instead; the write window
          # is one short `cat`, and the next path trigger regenerates a partial file.
          cat "$tmp" > /etc/nix/netrc
          chmod 0644 /etc/nix/netrc
          rm -f "$tmp"
        '';
      };
    in
    {
      # The same path the old module writes. A sops template writes the drop-ins here, so this
      # literal is part of the contract between the two modules.
      kdn.managed.directories = [ "/etc/nix/netrc.d" ];

      environment.systemPackages = [ kdn-gen-netrc ];

      systemd.paths."kdn-dynamic-netrc" = {
        description = "Generates /etc/nix/netrc from /etc/nix/netrc.d directory";
        wantedBy = [ "default.target" ];
        pathConfig.PathChanged = "/etc/nix/netrc.d";
        pathConfig.TriggerLimitIntervalSec = "1s";
        pathConfig.TriggerLimitBurst = 1;
      };
      systemd.services."kdn-dynamic-netrc" = {
        description = "Generates /etc/nix/netrc from /etc/nix/netrc.d directory";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          ExecStart = lib.getExe kdn-gen-netrc;
        };
      };
    };
}
