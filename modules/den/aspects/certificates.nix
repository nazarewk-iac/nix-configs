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
#   - `keyPath`  — the runtime path under `/run/secrets` that holds the decrypted private key, so no
#                  store path holds the secret.
#
# ## The storage rule
#
# The public certificate is `<directory>/<certFile>`, plain and committed. The private key is
# `<directory>/<keyFile>.sops`, a raw/binary SOPS file, committed. This aspect declares paths only.
# It never decrypts the key and never reads the file content.
#
# ## The `directory` default
#
# `directory` defaults to `hosts/<hostName>/certs`. The default reads `kdn.hostName`, so this aspect
# imports `../common/host-name.nix` by path. The module system dedupes an import by path, so many
# aspects load together and the option keeps one declaration.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. An empty `kdn.certificates.certs` is the no-op.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The root of this repository, as a relative path. `certPath` names the committed public
  # certificate inside the flake source tree, exactly as the old host files name
  # `"${kdnConfig.self}/hosts/<host>/certs/zellij.pub"`. It is a store path in a flake evaluation,
  # so it is safe to read at build time.
  repoRoot = ../../..;

  # One target module serves every class. The option set is identical in all four.
  target =
    { config, lib, ... }:
    let
      # The host name is read once here, outside the submodule, so the submodule default can close
      # over it. A submodule's own `config` cannot see the outer `kdn.hostName`.
      hostName = config.kdn.hostName;

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

          options.certFile = lib.mkOption {
            type = lib.types.str;
            default = "${name}.pub";
            description = "The public certificate filename. The file is `<directory>/<certFile>`, plain and committed.";
          };

          options.keyFile = lib.mkOption {
            type = lib.types.str;
            default = "${name}.key";
            description = "The private key filename. The stored key is `<directory>/<keyFile>.sops`, a raw/binary SOPS file.";
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

          options.certPath = lib.mkOption {
            type = lib.types.path;
            readOnly = true;
            description = "A store path to the committed public certificate, `<directory>/<certFile>`.";
          };

          options.keyPath = lib.mkOption {
            type = lib.types.path;
            readOnly = true;
            description = "The runtime path under `/run/secrets` that holds the decrypted private key.";
          };

          config.certPath = "${toString repoRoot}/${config.directory}/${config.certFile}";
          config.keyPath = "/run/secrets/kdn/certificates/${name}.key";
        };
    in
    {
      imports = [ ../common/host-name.nix ];

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
    };
in
{
  kdn.certificates.nixos = target;
  kdn.certificates.darwin = target;
  kdn.certificates.homeManager = target;
  kdn.certificates.devenv = target;
}
