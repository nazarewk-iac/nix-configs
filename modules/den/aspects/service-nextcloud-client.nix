# A Nextcloud sync timer for the root account, as a den aspect. It ports
# `modules/universal/services/nextcloud-client-nixos/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `kdn-nextcloud-nixos-sync`, and it runs that script every 15 minutes and on every
# change under `/root/Nextcloud`. The script reads a URL, a user name and a password from three
# files, then it calls `nextcloudcmd`.
#
# ## The port replaces a secret-tree read with three options
#
# The old module indexes `config.sops.secrets` by three literal names, in a `let` binding. A tree
# with no sops file holds none of those names, and the read stops the evaluation. The old module
# works around that: the whole `config` waits for `kdn.security.secrets.allowed`.
#
# This aspect declares three plain options instead, each one `null` by default. The consumer names
# the file paths, so the aspect carries no secret layout of anybody. The unit and the script land
# only when all three options hold a path, and only when the secrets policy allows a secret.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** The target writes `environment.systemPackages`.
#    Design B.
# 3. **`nextcloud-client` alone always installs.** The old module ties that package to the secret
#    gate. The package needs no secret, so it lands unconditionally here.
# 4. **The persist write becomes an output option.** See below.
#
# ## The persist directories become a read-only output
#
# The old module writes `kdn.disks.persist."usr/reproducible".users.root.directories`. An aspect
# must not write another aspect's option, so this aspect publishes the list under
# `persist.usrReproducibleRoot` and the consumer wires it in one line:
#
#     kdn.disks.persist."usr/reproducible".users.root.directories =
#       config.kdn.services.nextcloud-client.persist.usrReproducibleRoot;
#
# ## What it reads from another aspect
#
# `config.kdn.security.secrets.allowed or true` — the policy leaf of `./secrets.nix`. The `or`
# fallback keeps this aspect standalone. Deferred decision D2 permits the read.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.service-nextcloud-client.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.nextcloud-client;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      secretsAllowed = config.kdn.security.secrets.allowed or true;

      hasCredentials = cfg.urlPath != null && cfg.usernamePath != null && cfg.passwordPath != null;

      sync = pkgs.writeShellApplication {
        name = "kdn-nextcloud-nixos-sync";
        runtimeInputs = with pkgs; [
          coreutils
          nextcloud-client
        ];
        runtimeEnv.url_path = toString cfg.urlPath;
        runtimeEnv.username_path = toString cfg.usernamePath;
        runtimeEnv.password_path = toString cfg.passwordPath;
        text = ''
          url="$(cat "$url_path")"
          username="$(cat "$username_path")"
          domain="''${url##*://}"
          domain="''${domain%%/*}"
          domain="''${domain##*@}"
          dir="$HOME/Nextcloud/$username@$domain"
          mkdir -p "$dir"
          nextcloudcmd -u "$username" -p "$(cat "$password_path")" "$@" "$dir" "$url"
        '';
      };
    in
    {
      options.kdn.services.nextcloud-client.urlPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The file that holds the server URL, as a path on the running machine. The timer and the
          script land only when this option, `usernamePath` and `passwordPath` all hold a path.
        '';
      };

      options.kdn.services.nextcloud-client.usernamePath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The file that holds the user name, as a path on the running machine.";
      };

      options.kdn.services.nextcloud-client.passwordPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The file that holds the password, as a path on the running machine.";
      };

      options.kdn.services.nextcloud-client.persist.usrReproducibleRoot = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The directories this aspect wants under the root account, relative to the home
          directory. The consumer wires the list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages [ pkgs.nextcloud-client ];
          kdn.services.nextcloud-client.persist.usrReproducibleRoot = [
            "Nextcloud"
          ];
        }
        (lib.mkIf (secretsAllowed && hasCredentials) {
          environment.systemPackages = filterPackages [ sync ];
          systemd.timers."kdn-nextcloud-nixos-sync" = {
            description = "Synchronizes /root/Nextcloud directory";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            timerConfig.OnUnitActiveSec = "15m";
          };
          systemd.paths."kdn-nextcloud-nixos-sync" = {
            description = "Synchronizes /root/Nextcloud directory";
            wantedBy = [ "multi-user.target" ];
            pathConfig.PathChanged = "/root/Nextcloud";
            pathConfig.TriggerLimitIntervalSec = "10s";
            pathConfig.TriggerLimitBurst = 1;
          };
          systemd.services."kdn-nextcloud-nixos-sync" = {
            description = "Synchronizes /root/Nextcloud directory";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            environment.HOME = "/root";
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;
            serviceConfig.ExecStart = lib.escapeShellArgs [
              (lib.getExe sync)
              "--non-interactive"
            ];
          };
        })
      ];
    };
}
