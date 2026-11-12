# The `certificates` aspect. It declares the leaf certificate option set and exposes the two paths
# a consumer reads.
#
# ## What it does
#
# It declares one option, `kdn.certificates.certs`, an attribute set keyed by certificate name. Each
# entry names the signing CA, the certificate kind, the subject common name, the SANs or principals,
# the files that hold the certificate and key, and the policy values the `kdn-certs` CLI reads.
#
# It signs nothing. The `kdn-certs` CLI reads the declarations and generates the files. The aspect
# exposes two derived values per leaf:
#
#   - `certPath` — a store path to the public certificate, safe to read at build time.
#   - `keyPath`  — the runtime path that holds the decrypted private key, so no store path holds the
#                  secret.
#
# ## The storage rule
#
# The public certificate is `<repoRoot>/<directory>/<certFile>`, plain and committed. The private key
# is `<repoRoot>/<keyDirectory>/<keyFile>.sops`, a raw/binary SOPS file, committed. This aspect
# declares paths only. It never decrypts the key and never reads the file content.
#
# The two directories are separate so a secret and a public artefact cannot be confused. For an
# `ssh-host` leaf the key defaults to `hosts/<hostName>/ssh-keys` and the certificate to
# `hosts/<hostName>/certs`; every other leaf keeps both in `directory`.
#
# ## The repository root
#
# `repoRoot` is a consumer-provided option. It names the root of the tree that holds the certificate
# files. A declared certificate needs it, so a missing value is a hard error at the one point that
# reads it. The aspect holds **no** implicit default: an external adopter who imports this aspect
# gets a path inside their own tree, never inside the `nix-configs` store tree.
#
# ## The private key and sops-nix
#
# The three host and home classes import the pinned `sops-nix` module and write one `sops.secrets`
# entry per declared key:
#
#   - `format = "binary"` — sops writes the raw key bytes, so the committed key is a raw/binary SOPS
#     file and not a YAML or JSON document.
#   - `sopsFile = <repoRoot>/<directory>/<keyFile>.sops` — the committed raw/binary SOPS file.
#   - `keyPath` reads `config.sops.secrets.<name>.path`, so the consumer reads the decrypted runtime
#     path and no store path holds the secret.
#
# A leaf that names `owner` writes `sops.secrets.<name>.owner = <owner>`. The `nixos` sops module
# derives the group from the owner; the `darwin` module defaults the group to `staff`. `mode` stays
# `0400`. A service that runs as a non-root user needs it, because the default key file is
# root-only.
#
# The `devenv` class carries no sops-nix module. Its `keyPath` is the fixed runtime path
# `/run/secrets/kdn/certificates/<name>.key`, which the `kdn-certs` CLI fills with its own decrypt
# primitive (`sops decrypt --output-type binary`). A devenv shell owns no system activation, so it
# cannot run the sops-nix installer.
#
# ## The `directory` and `keyDirectory` defaults
#
# `directory` defaults to `hosts/<hostName>/certs`, and `keyDirectory` to
# `hosts/<hostName>/ssh-keys` for `ssh-host` leaves (to `directory` otherwise). The defaults read
# `kdn.hostName`, so this aspect imports `../common/host-name.nix` by path. The module system dedupes
# an import by path, so many aspects load together and the option keeps one declaration.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. An empty `kdn.certificates.certs` is the no-op.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only.
#    `inputs` comes from this file's own scope, because the check harness passes `pkgs` alone to a
#    target.
{ inputs, ... }:
let
  # The sops-nix secret name of one leaf key. The nested name keeps the decrypted path at
  # `/run/secrets/kdn/certificates/<name>.key`, the path the design § 4.1 states.
  secretName = name: "kdn/certificates/${name}.key";

  # Where the decrypted private key of one leaf lives. A sops-nix class reads the runtime path it
  # declares; an `ssh-host` leaf is never a sops secret, so it reads the path `kdnctl` deploys to.
  keyPathForClass =
    { config, name, cert }:
    if cert.type == "ssh-host" then
      "${cert.deployedDirectory}/${cert.keyFile}"
    else
      config.sops.secrets.${secretName name}.path;

  # One target module factory. `sopsModule` is the sops-nix module of the class, or `null` for the
  # `devenv` class, which carries no sops-nix. `keyPathFor` reads the decrypted runtime path of one
  # key from the outer target config. `ownerSupport` records whether the class's sops module declares
  # the `owner` option: the `nixos` and `darwin` modules do, the `homeManager` module does not.
  mkTarget =
    {
      sopsModule ? null,
      keyPathFor,
      ownerSupport ? false,
      trustCAs ? false,
      trustClass ? "nixos",
    }:
    { config, lib, pkgs, ... }:
    let
      cfg = config.kdn.certificates;

      # The outer config, captured before the submodule shadows `config`.
      outerConfig = config;

      # The repository root the consumer names. A declared certificate needs it, so a missing value
      # is a hard error at the one point that reads it. The binding stays lazy: an empty
      # `kdn.certificates.certs` never forces it.
      repoRoot =
        if cfg.repoRoot == null then
          throw "kdn.certificates: set `kdn.certificates.repoRoot` when you declare a certificate"
        else
          cfg.repoRoot;

      # The host name is read once here, outside the submodule, so the submodule default can close
      # over it. A submodule's own `config` cannot see the outer `kdn.hostName`.
      hostName = config.kdn.hostName;

      # A single PEM bundle of every CA the ca-dag declares, so Node (which takes one
      # file) can trust the whole set. Lazy: only forced when CA trust is enabled.
      caBundle = pkgs.writeText "kdn-ca-bundle.pem" (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            _: ca: builtins.readFile "${toString repoRoot}/${ca.directory}/${ca.certFile}"
          ) (config.kdn.ca-dag.cas or { })
        )
      );

      # Trust emission differs per class (a devenv/HM module has no security.pki).
      trustSection =
        if trustClass == "nixos" || trustClass == "darwin" then
          {
            security.pki.certificateFiles = lib.mapAttrsToList (
              _: ca: "${toString repoRoot}/${ca.directory}/${ca.certFile}"
            ) (config.kdn.ca-dag.cas or { });
            environment.variables.NODE_EXTRA_CA_CERTS = "${caBundle}";
          }
        else if trustClass == "home" then
          { home.sessionVariables.NODE_EXTRA_CA_CERTS = "${caBundle}"; }
        else if trustClass == "devenv" then
          { env.NODE_EXTRA_CA_CERTS = "${caBundle}"; }
        else
          { };

      certsSubmodule =
        { name, config, ... }:
        {
          options.ca = lib.mkOption {
            type = lib.types.str;
            description = "The signing CA name, from `kdn.ca-dag.cas`.";
          };

          options.type = lib.mkOption {
            type = lib.types.enum [
              "tls-server"
              "tls-client"
              "ssh-user"
              "ssh-host"
            ];
            description = "The certificate kind. `tls-server` and `tls-client` read `sans`; `ssh-user` and `ssh-host` read `principals`.";
          };

          options.commonName = lib.mkOption {
            type = lib.types.str;
            description = "The subject common name of the leaf.";
          };

          options.sans = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "The TLS subject alternative names.";
          };

          options.principals = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "The SSH principals.";
          };

          options.directory = lib.mkOption {
            type = lib.types.str;
            default = "hosts/${hostName}/certs";
            description = "The repo-relative directory of the leaf files.";
          };

          options.keyDirectory = lib.mkOption {
            type = lib.types.str;
            default = if config.type == "ssh-host" then "hosts/${hostName}/ssh-keys" else config.directory;
            description = ''
              The repo-relative directory that holds the private key
              (`<keyDirectory>/<keyFile>.sops`). Defaults to `hosts/<hostName>/ssh-keys` for
              `ssh-host` leaves and to `directory` otherwise.

              SSH host keys live apart from their certificates on purpose: the key is a secret that
              must never leave the host unencrypted, while the certificate is public and is read by
              the signing tool, the inventory that generates `known_hosts`, and anything that pins
              the host. Keeping the two in one directory made it easy to commit the wrong one.
            '';
          };

          options.certFile = lib.mkOption {
            type = lib.types.str;
            default = "${name}.pub";
            description = "The public certificate filename. The file is `<directory>/<certFile>` under `repoRoot`, plain and committed.";
          };

          options.keyFile = lib.mkOption {
            type = lib.types.str;
            default = "${name}.key";
            description = "The private key filename. The stored key is `<directory>/<keyFile>.sops` under `repoRoot`, a raw/binary SOPS file.";
          };

          options.keySource = lib.mkOption {
            type = lib.types.enum [
              "external"
              "managed"
            ];
            description = "`external` means the key pre-exists. `managed` means the CLI generates the key.";
          };

          options.minGenerationDate = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              The oldest allowed generation date, in ISO 8601 with arbitrary precision. A missing
              component takes its lowest value, so `2026` means `2026-01-01T00:00:00Z`. The parser
              and the comparison belong to the CLI.
            '';
          };

          options.owner = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              The owner of the decrypted key file. When set, the aspect writes
              `sops.secrets.<name>.owner = <owner>`, and sops-nix derives the group from the owner.
              `mode` stays `0400`. A service that runs as a non-root user needs this, because the
              default key file is root-only.
            '';
          };

          options.deployedDirectory = lib.mkOption {
            type = lib.types.str;
            default = "/etc/ssh";
            description = ''
              The runtime directory that holds the decrypted private key of an `ssh-host` leaf.
              `keyPath` is `<deployedDirectory>/<keyFile>` for that type, which puts the deployed
              key at `/etc/ssh/ssh_host_ed25519_key` — the path sshd reads and the path
              `kdn.security.secrets.age` derives the host's SOPS identity from. One file is both
              the host identity and the identity that decrypts the host's secrets.

              An SSH host key is never delivered by sops-nix. It is the host's identity, and on
              this fleet it is also going to be a SOPS age identity, so a host that could decrypt
              its own key from the repository would make the key's custody circular. The key is
              encrypted to operator identities only (see `.sops.yaml`) and written to this
              directory by `kdnctl host ensure ssh-host-keys`, which runs on an operator machine
              with the YubiKey present. The directory is preserved across reboots.

              The other types keep reading the sops-nix runtime path, because a service on the
              host decrypts those at boot.
            '';
          };

          options.certPath = lib.mkOption {
            type = lib.types.path;
            readOnly = true;
            description = "A store path to the committed public certificate, `<repoRoot>/<directory>/<certFile>`.";
          };

          options.keyPath = lib.mkOption {
            type = lib.types.path;
            readOnly = true;
            description = "The runtime path that holds the decrypted private key.";
          };

          config.certPath = "${toString repoRoot}/${config.directory}/${config.certFile}";
          config.keyPath = keyPathFor {
            config = outerConfig;
            inherit name;
            cert = config;
          };
        };
    in
    {
      imports = [ ../common/host-name.nix ] ++ lib.optional (sopsModule != null) sopsModule;

      options.kdn.certificates.repoRoot = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = ../../..;
        description = ''
          The root of the tree that holds the certificate files. A declared certificate needs it, so
          set it when `kdn.certificates.certs` is not empty.

          The aspect holds no implicit default. An external adopter names their own tree root, so
          `certPath` never points into the `nix-configs` store tree.
        '';
      };

      options.kdn.certificates.certs = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule certsSubmodule);
        default = { };
        example = {
          zellij-web = {
            ca = "kdn";
            type = "tls-server";
            commonName = "example.invalid";
            sans = [ "example.invalid" ];
            keySource = "managed";
          };
        };
        description = "The leaf certificates, keyed by name.";
      };

      # The sops-nix wiring. It runs only when a certificate is declared, so an empty option set
      # stays a true no-op. The `devenv` class carries no sops-nix module, so it writes no secret.
      #
      # `ssh-host` leaves are skipped on purpose: a host must not be able to decrypt its own
      # identity. Their key is written to `deployedDirectory` by `kdnctl`, out of band.
      #
      # `owner` is written only when the leaf names one and the class's sops module declares the
      # option. The `nixos` module then derives the group from the owner (`users.<owner>.group`);
      # the `darwin` module defaults the group to `staff`. `mode` stays `0400`. A service that runs
      # as a non-root user needs it, because the default key file is root-only. The `homeManager`
      # sops module declares no `owner`, so that class ignores it.
      config = lib.mkMerge [
        # Key secrets exist only for hosts that DECLARE a certificate.
        (lib.mkIf (cfg.certs != { }) (
          lib.optionalAttrs (sopsModule != null) {
            sops.secrets = lib.mapAttrs' (
              name: cert:
              lib.nameValuePair (secretName name) (
                {
                  format = "binary";
                  sopsFile = "${toString repoRoot}/${cert.keyDirectory}/${cert.keyFile}.sops";
                }
                // lib.optionalAttrs (ownerSupport && cert.owner != null) { owner = cert.owner; }
              )
            ) (lib.filterAttrs (_: cert: cert.type != "ssh-host") cfg.certs);
          }
        ))
        # CA trust is INDEPENDENT of declaring a leaf: a pure CLIENT host still needs to
        # trust the internal CA to reach the HTTPS gateway. Gated on the ca-dag having a
        # CA (so importing ca-dag, not declaring a cert, is the switch). Requires
        # `repoRoot` (the CA certs are located relative to it).
        (lib.mkIf (trustCAs && (config.kdn.ca-dag.cas or { }) != { }) trustSection)
      ];
    };
in
{
  kdn.certificates.nixos = mkTarget {
    sopsModule = inputs.sops-nix.nixosModules.sops;
    ownerSupport = true;
    trustCAs = true;
    keyPathFor = keyPathForClass;
  };

  kdn.certificates.darwin = mkTarget {
    sopsModule = inputs.sops-nix.darwinModules.default;
    ownerSupport = true;
    trustCAs = true;
    keyPathFor = keyPathForClass;
  };

  kdn.certificates.homeManager = mkTarget {
    sopsModule = inputs.sops-nix.homeManagerModules.sops;
    trustCAs = true;
    trustClass = "home";
    keyPathFor = keyPathForClass;
  };

  # The `devenv` class carries no sops-nix module. The CLI decrypt primitive fills this path.
  kdn.certificates.devenv = mkTarget {
    trustCAs = true;
    trustClass = "devenv";
    keyPathFor =
      { cert, name, ... }:
      if cert.type == "ssh-host" then
        "${cert.deployedDirectory}/${cert.keyFile}"
      else
        "/run/secrets/kdn/certificates/${name}.key";
  };
}
