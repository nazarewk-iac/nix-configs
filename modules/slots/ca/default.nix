# KDN certificate authority slot.
#
# Trusts one or more private CAs as system CA authorities, so every leaf
# certificate they sign verifies with no per-application cert hack. Each CA
# instance is keyed by name (`kdn.ca.<name>`). Mount policy per machine:
#   - ca.pub        -> every machine (system CA authority via security.pki)
#   - ca.key.sops   -> a development machine only, as an encrypted blob at
#                      /etc/kdn/ca/<name>.key.sops (0400, root, manual
#                      reference only -- never decrypted by this slot)
#   - <host>/<name>.{key,pub} -> only a machine that uses the certificates; do
#                      NOT mount a leaf pub of a solution hosted elsewhere.
#
# This slot is STANDALONE. It uses only `lib`, `pkgs`, `config`, and plain
# NixOS options (`environment.etc`, `security.pki.certificateFiles`). See
# .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.ca;

  enabledCas = lib.filterAttrs (_: ca: ca.enable) cfg;

  # One /etc/kdn/ca/<name>.pub + optional <name>.key.sops entry per instance.
  toEtc =
    name: ca:
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

  caSubmodule = { ... }: {
    options = {
      enable = lib.mkEnableOption "this CA as a system CA authority";

      certFile = lib.mkOption {
        type = lib.types.path;
        example = "/nix/store/...-my-ca/ca.pub";
        description = ''
          Path to the public CA certificate (PEM). Mounted at
          /etc/kdn/ca/<name>.pub and added to the system CA bundle.
        '';
      };

      keySopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/nix/store/...-my-ca/ca.key.sops";
        description = ''
          Path to the SOPS-encrypted CA private key (raw/binary .sops file).
          Mounted at /etc/kdn/ca/<name>.key.sops (0400, root) as an encrypted
          blob, for manual reference only — never decrypted by this slot.
        '';
      };
    };
  };
in
{
  options.kdn.ca = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule caSubmodule);
    default = { };
    example = {
      my-ca.enable = true;
      my-ca.certFile = "/etc/nixos/data/ca.pub";
    };
    description = "CA instances, keyed by name, to trust as system CAs.";
  };

  config = lib.mkIf (enabledCas != { }) {
    nixos = {
      environment.etc = lib.mkMerge (lib.mapAttrsToList toEtc enabledCas);

      # Add every enabled CA to the system bundle (build-time path; security.pki
      # bakes it into the store's CA bundle).
      security.pki.certificateFiles = lib.concatMap (ca: [ ca.certFile ]) (lib.attrValues enabledCas);
    };
  };
}
