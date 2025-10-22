{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.fs.encryption;

  systemd-cryptsetup = pkgs.runCommand "systemd-cryptsetup-bin" {} ''
    mkdir -p $out/bin
    ln -sf ${pkgs.systemd}/lib/systemd/systemd-cryptsetup $out/bin/
  '';
in {
  options.kdn.toolset.fs.encryption = {
    enable = lib.mkEnableOption "disk encryption tooling setup";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; (
      [
        clevis
        cryptsetup
        jose
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
          runtimeInputs = [systemd-cryptsetup];
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
  };
}
