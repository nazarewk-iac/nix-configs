{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.fs.encryption;

  systemd-cryptsetup = pkgs.kdn.systemd-cryptsetup;
in
{
  options.kdn.toolset.fs.encryption = {
    enable = lib.mkEnableOption "disk encryption tooling setup";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.env.packages =
            with pkgs;
            (
              [
                clevis
              ]
              ++ lib.optionals (!stdenv.hostPlatform.isDarwin) [
                # this is broken on Darwin
                jose # JSON Web Token tool, https://github.com/latchset/jose
              ]
            );
        }
        (kdnConfig.util.ifTypes [ "nixos" ] {
          kdn.env.packages =
            with pkgs;
            (
              [
                cryptsetup
                systemd-cryptsetup
              ]
              ++ [
                sbctl
                tpm2-tools
                tpm2-tss
              ]
              ++ [
                (pkgs.writeShellApplication {
                  name = "kdn-systemd-zfs-decrypt";
                  runtimeInputs = [ systemd-cryptsetup ];
                  text = ''
                    set -eEuo pipefail
                    set -x

                    usage() {
                      cat <<'EOF' >&2
                    kdn-systemd-zfs-decrypt XXX-main-crypted /dev/disk/by-id/encrypted-zpool /dev/disk/by-id/header-partition
                    EOF
                      exit 1
                    }

                    main() {
                      name="$1"
                      disk="$2"
                      header="$3"

                      systemd-cryptsetup attach "$name" "$disk" - header="$header"
                    }

                    main "$@" || usage
                  '';
                })
              ]
            );
        })
      ]
    ))
  ];
}
