# The `ca-dag` aspect. It declares the certificate-authority graph as data.
#
# ## What it does
#
# It declares one option, `kdn.ca-dag.cas`, an attribute set keyed by CA name. Each entry names one
# node of a directed acyclic graph: a root or an intermediate, its parent, its subject common name,
# the files that hold its certificate and key, and the policy values the `kdn-certs` CLI reads.
#
# It emits no configuration, holds no system trust and starts no process. The `kdn-certs` CLI reads
# the graph and walks it in topological order. A consumer that reads the graph pays no package
# build.
#
# ## Why it is separate from `kdn.ca`
#
# `kdn.ca` trusts a CA as a system CA. It has the `nixos` class only, and it mounts a public
# certificate into `/etc/kdn/ca`. It never generates a key and never signs a certificate.
#
# This aspect declares the graph. The two aspects have different classes, different jobs and
# different option trees. `kdn.ca` declares `options.kdn.ca`; this aspect declares
# `options.kdn.ca-dag`, so the two trees cannot clash.
#
# ## The storage rule
#
# The public certificate is `<directory>/<certFile>`, plain and committed. The private key is
# `<directory>/<keyFile>.sops`, a raw/binary SOPS file, committed. This aspect declares paths only.
# It never decrypts the key and never reads the file content.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. An empty `kdn.ca-dag.cas` is the no-op.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The option set is identical in all four classes, so one module serves each class key.
  optionsModule =
    { lib, ... }:
    {
      options.kdn.ca-dag.cas = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.type = lib.mkOption {
                type = lib.types.enum [
                  "root"
                  "intermediate"
                ];
                description = "The node class in the CA graph. A root signs an intermediate; an intermediate signs a leaf.";
              };

              options.parent = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "The parent CA name. A root names no parent. A parent that names no CA is a hard error in the CLI.";
              };

              options.commonName = lib.mkOption {
                type = lib.types.str;
                description = "The subject common name of the CA.";
              };

              options.directory = lib.mkOption {
                type = lib.types.str;
                default = "data/ca";
                description = "The repo-relative directory of the CA files.";
              };

              options.certFile = lib.mkOption {
                type = lib.types.str;
                default = "${name}.crt";
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
                description = "`external` means the key pre-exists, for example a YubiKey-backed key. `managed` means the CLI generates the key.";
              };

              options.provisioner = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "The smallstep provisioner name.";
              };

              options.ssh = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "The CA also signs SSH certificates.";
              };

              options.minGenerationDate = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  The oldest allowed generation date, in ISO 8601 with arbitrary precision. A
                  missing component takes its lowest value, so `2026` means `2026-01-01T00:00:00Z`.
                  The parser and the comparison belong to the CLI.
                '';
              };
            }
          )
        );
        default = { };
        example = {
          kdn = {
            type = "root";
            commonName = "KDN root CA";
            keySource = "external";
          };
        };
        description = "The certificate-authority graph, keyed by CA name.";
      };
    };
in
{
  kdn.ca-dag.nixos = optionsModule;
  kdn.ca-dag.darwin = optionsModule;
  kdn.ca-dag.homeManager = optionsModule;
  kdn.ca-dag.devenv = optionsModule;
}
