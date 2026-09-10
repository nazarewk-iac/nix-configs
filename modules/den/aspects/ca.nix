# The `ca` slot, as a den aspect. It ports `modules/slots/ca/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It trusts one or more certificate authorities as system CA authorities. A leaf certificate that
# such a CA signs then verifies with no per-application certificate hack. Each instance is keyed by
# name, so `kdn.ca.<name>`.
#
# Per instance it mounts:
#   - `/etc/kdn/ca/<name>.pub`      the public certificate, 0444, plus one `security.pki` entry
#   - `/etc/kdn/ca/<name>.key.sops` the encrypted private key, 0400 root, optional
#
# The aspect never decrypts the key. It mounts the encrypted blob for manual reference only.
#
# ## Where the option lives, and why
#
# The slot declares `options.kdn.ca` at **slot** scope and reads it from there. This aspect declares
# the option **inside its own `nixos` target**, next to the code that reads it. That is the drop-in
# shape: one plain NixOS module both declares the option and serves it, so a consumer imports the
# module and sets `kdn.ca.<name>` in their own configuration. Nothing else is needed.
#
# The two trees cannot clash. The slot declares the option in a slot evaluation; no slot declares it
# in a `nixos` target. So a machine can hold both trees at once.
#
# **An aspect stays universal, and the data stays with the consumer.** The creator stated this
# constraint on 2026-09-10: the reusable code unit carries no personal data, and the creator's own
# configuration and data live in one folder. So this file holds no certificate path. The test
# entity at ../../checks/den-mvp/host-nixos/ generates its own throwaway certificates.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `kdn.ca.<name>.enable` is not that switch —
#    it selects one instance out of an attribute set, and an empty set is already a no-op.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.ca.nixos =
    { config, lib, ... }:
    let
      enabled = lib.filterAttrs (_: ca: ca.enable) config.kdn.ca;

      # One `/etc/kdn/ca/<name>.pub` entry per instance, plus the optional encrypted key.
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

      caSubmodule = {
        options.enable = lib.mkEnableOption "this CA as a system CA authority";

        options.certFile = lib.mkOption {
          type = lib.types.path;
          example = "/nix/store/…-my-ca/ca.pub";
          description = ''
            Path to the public CA certificate, in PEM form. The aspect mounts it at
            `/etc/kdn/ca/<name>.pub` and adds it to the system CA bundle.
          '';
        };

        options.keySopsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/nix/store/…-my-ca/ca.key.sops";
          description = ''
            Path to the SOPS-encrypted CA private key, as a raw binary `.sops` file. The aspect
            mounts it at `/etc/kdn/ca/<name>.key.sops`, mode 0400, owner root. It is an encrypted
            blob for manual reference only. This aspect never decrypts it.
          '';
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
        description = "CA instances, keyed by name, to trust as system CA authorities.";
      };

      # An empty attribute set makes the whole aspect a no-op, so inclusion alone changes nothing.
      config = lib.mkIf (enabled != { }) {
        environment.etc = lib.mkMerge (lib.mapAttrsToList toEtc enabled);

        # `security.pki` bakes the bundle at build time, so each path must exist in the store.
        security.pki.certificateFiles = lib.mapAttrsToList (_: ca: ca.certFile) enabled;
      };
    };
}
