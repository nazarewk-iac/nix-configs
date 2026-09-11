# The iperf3 throughput server and a client wrapper, as a den aspect. It ports
# `modules/universal/services/iperf3/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs the iperf3 daemon and opens its port, and it installs `kdn-iperf3-client`, a wrapper that
# picks up the client credentials from a directory the consumer names.
#
# ## The port replaces a secret-tree read with four options
#
# The old module indexes `kdn.security.secrets.sops.secrets.default.networking.iperf-server.*` by
# literal name, so it needs that tree and it carries this repository's own secret layout. The sops
# tree has no den home yet, and the layout is consumer data. So this aspect declares four plain
# options instead, each one `null` by default:
#
#   - `server.privateKeyPath` and `server.authorizedUsersPath` — the daemon credentials
#   - `client.publicKeyPath` and `client.passwordDir` — what the wrapper reads
#
# The daemon takes RSA authentication only when **both** server paths are set. The wrapper installs
# only when **both** client paths are set. So an adopter that names nothing gets a plain,
# unauthenticated server and no wrapper, and it names no path of somebody else.
#
# ## What the port changes
#
# 1. **`enable` goes**, and the two nested flags become `server.use` and `client.use`. Rule 2 forbids
#    a reachable `enable` option.
# 2. **`kdn.env.packages` does not survive.** The target writes `environment.systemPackages`.
#    Design B.
# 3. **The whole module no longer waits for the secrets policy.** The old `config` sits behind
#    `kdn.security.secrets.allowed`, because it cannot read the secret tree otherwise. This aspect
#    reads no secret tree, so only the **credential** half keeps that gate. A consumer that forbids
#    a secret still gets the plain server.
#
# ## What it reads from another aspect
#
# `config.kdn.security.secrets.allowed or true` — the policy leaf of `./secrets.nix`. The `or`
# fallback keeps this aspect standalone: a consumer that includes no `secrets` aspect declares no
# such option, and the read then yields `true`. Deferred decision D2 permits the read.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.service-iperf3.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.iperf3;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      secretsAllowed = config.kdn.security.secrets.allowed or true;

      hasServerCredentials = cfg.server.privateKeyPath != null && cfg.server.authorizedUsersPath != null;
      hasClientCredentials = cfg.client.publicKeyPath != null && cfg.client.passwordDir != null;

      clientScript = pkgs.writeShellApplication {
        name = "kdn-iperf3-client";
        runtimeInputs = [ config.services.iperf3.package ];
        text = ''
          : "''${IPERF3_USERNAME:="${cfg.client.defaultUsername}"}"

          args=(
            --username "$IPERF3_USERNAME"
            --rsa-public-key-path ${lib.escapeShellArg cfg.client.publicKeyPath}
          )
          IPERF3_PASSWORD="$(cat ${lib.escapeShellArg cfg.client.passwordDir}/"$IPERF3_USERNAME")" \
            iperf3 "''${args[@]}" --client "$@"
        '';
      };
    in
    {
      options.kdn.services.iperf3.server.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Run the iperf3 daemon and open its port.

          The name is `use`, not `enable`: an aspect declares no reachable `enable` option.
        '';
      };

      options.kdn.services.iperf3.client.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = "Install the `kdn-iperf3-client` wrapper.";
      };

      options.kdn.services.iperf3.server.privateKeyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The RSA private key the daemon presents, as a path on the running machine.

          `null` leaves the daemon unauthenticated. Both this option and
          `server.authorizedUsersPath` must hold a path before the daemon asks for a credential.
        '';
      };

      options.kdn.services.iperf3.server.authorizedUsersPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The authorized-users CSV the daemon reads, as a path on the running machine. `null`
          leaves the daemon unauthenticated.
        '';
      };

      options.kdn.services.iperf3.client.publicKeyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The RSA public key the wrapper sends, as a path on the running machine. The wrapper
          installs only when this option and `client.passwordDir` both hold a path.
        '';
      };

      options.kdn.services.iperf3.client.passwordDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The directory that holds one password file per user name, as a path on the running
          machine. The wrapper reads `<passwordDir>/<username>`.
        '';
      };

      options.kdn.services.iperf3.client.defaultUsername = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "measure";
        description = ''
          The user name the wrapper takes when `IPERF3_USERNAME` is unset. The empty string forces
          the caller to set that variable.
        '';
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.server.use {
          services.iperf3.enable = true;
          services.iperf3.openFirewall = true;
        })
        (lib.mkIf (cfg.server.use && secretsAllowed && hasServerCredentials) {
          systemd.services.iperf3.after = [ "kdn-secrets.target" ];
          systemd.services.iperf3.requires = [ "kdn-secrets.target" ];
          systemd.services.iperf3.serviceConfig.LoadCredential = [
            "private.pem:${cfg.server.privateKeyPath}"
            "users.csv:${cfg.server.authorizedUsersPath}"
          ];
          services.iperf3.rsaPrivateKey = null;
          services.iperf3.authorizedUsersFile = null;
          services.iperf3.extraFlags = [
            "--rsa-private-key-path"
            "%d/private.pem"
            "--authorized-users-path"
            "%d/users.csv"
          ];
        })
        (lib.mkIf (cfg.client.use && hasClientCredentials) {
          environment.systemPackages = filterPackages [ clientScript ];
        })
      ];
    };
}
