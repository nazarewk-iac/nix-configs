# KDN certificate authority slot.
#
# Trusts one or more KDN CAs as system CA authorities so the leaf certificates
# they sign (e.g. the brys LLM leaf cert) verify without per-app cert hacks.
# Each CA instance is keyed by name (`kdn.ca.<name>`), e.g. `kdn.ca.kdn` for
# KDN's private CA. Mount policy per machine:
#   - ca.pub        -> every machine (system CA authority via security.pki)
#   - ca.key.sops   -> development machines only (oams & brys), as an encrypted
#                      blob at /etc/kdn/ca/<name>.key.sops (0400, root, manual
#                      reference only -- never decrypted by this slot)
#   - <host>/<name>.{key,pub} -> only machines utilising the certificates; do
#                      NOT mount leaf pubs of solutions hosted elsewhere.
#
# This slot is STANDALONE. It uses only `lib`, `pkgs`, `config`, and plain
# NixOS options (`environment.etc`, `security.pki.certificateFiles`). See
# .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.ca;

  enabledCas = lib.filterAttrs (_: ca: ca.enable) cfg;

  # One /etc/kdn/ca/<name>.pub + optional <name>.key.sops entry per instance.
  toEtc = name: ca:
    {
      "kdn/ca/${name}.pub" = {
        source = ca.certFile;
        mode = "0444";
      };
    }
    // lib.optionalAttrs (ca.keySopsFile != null) {
      "kdn/ca/${name}.key.sops" = {
        source = ca.keySopsFile;
        mode = "0400";
        user = "root";
        group = "root";
      };
    };

  caSubmodule = {...}: {
    options = {
      enable = lib.mkEnableOption "this CA as a system CA authority";

      certFile = lib.mkOption {
        type = lib.types.path;
        example = "/nix/store/.../data/ca.pub";
        description = ''
          Path to the public CA certificate (PEM). Mounted at
          /etc/kdn/ca/<name>.pub and added to the system CA bundle.
        '';
      };

      keySopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to the SOPS-encrypted CA private key (raw/binary .sops file),
          e.g. data/ca.key.sops. Mounted at /etc/kdn/ca/<name>.key.sops (0400,
          root) as an encrypted blob, for manual reference only — never
          decrypted by this slot.
        '';
      };
    };
  };
in {
  options.kdn.ca = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule caSubmodule);
    default = {};
    example = {
      kdn.certFile = "\${kdnConfig.self}/data/ca.pub";
      kdn.keySopsFile = "\${kdnConfig.self}/data/ca.key.sops";
    };
    description = "CA instances, keyed by name, to trust as system CAs.";
  };

  config = lib.mkIf (enabledCas != {}) {
    nixos = {
      environment.etc = lib.mkMerge (lib.mapAttrsToList toEtc enabledCas);

      # Add every enabled CA to the system bundle (build-time path; security.pki
      # bakes it into the store's CA bundle).
      security.pki.certificateFiles = lib.concatMap (ca: [ca.certFile]) (
        lib.attrValues enabledCas
      );
    };
  };
}
