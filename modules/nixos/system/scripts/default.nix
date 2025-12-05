{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.system.scripts;
in {
  options.kdn.system.scripts = {
    setup-key-files = lib.mkOption {
      readOnly = true;
      default = pkgs.writeShellApplication {
        name = "kdn-disks-setup-key-files-${config.kdn.hostName}";
        runtimeInputs = with pkgs; [
          coreutils
          pass
        ];
        text = lib.pipe config.kdn.disks.luks.volumes [
          lib.attrsets.attrsToList
          (builtins.filter ({
            name,
            value,
          }:
            value.keyFile != null))
          (builtins.map ({
            name,
            value,
          }: ''
            if test -e "$PASSWORD_STORE_DIR/luks/${name}/keyfile.gpg" ; then
              echo "luks/${name}/keyfile already exists, skipping..."
            else
              dd if=/dev/random bs=1 count=2048 of=/dev/stdout | pass insert "$@" --multiline "luks/${name}/keyfile"
              echo "luks/${name}/keyfile generated."
            fi
          ''))
          (builtins.concatStringsSep "\n")
          (text: ''
            set -x
            : "''${PASSWORD_STORE_DIR:="$HOME/.password-store"}"
            ${text}
          '')
        ];
      };
    };

    install = lib.mkOption {
      readOnly = true;
      default = pkgs.writeShellApplication {
        name = "kdn-install-${config.kdn.hostName}";
        runtimeInputs = with pkgs; [
          moreutils # sponge
          nixos-anywhere
          openssh
          pass
          ssh-to-age
        ];
        text = let
          volumes = lib.pipe config.kdn.disks.luks.volumes [
            lib.attrsets.attrsToList
            (builtins.filter ({
              name,
              value,
            }:
              value.keyFile != null))
          ];
          perVolume = fn:
            lib.pipe volumes [
              (builtins.map ({
                name,
                value,
              }:
                fn name value))
              (builtins.concatStringsSep "\n")
            ];
        in ''

          tempdir="$(mktemp -d /tmp/kdn-install-${config.kdn.hostName}.XXXXXX)"
          mkdir -p "$tempdir"
          chmod 700 "$tempdir"
          trap 'rm -rf "$tempdir" || :' EXIT

          runSSH() {
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$connection" "''${*@Q}"
          }

          addEncryptionKeyArg() {
            local name="$1" keyFile="$2"
            pass show "luks/$name/keyfile" > "$tempdir/$name.key"
            args+=( --disk-encryption-keys "$keyFile" "$tempdir/$name.key" )
          }

          ensureLineInFile() {
            local file="$1" pattern="$2" line="$3"
            if ! grep -qF "$line" "$file" &>/dev/null ; then
              awk -v line="$line" "/$pattern/ {print line} {print}" "$file" | sponge "$file"
            fi
          }

          set -x
          connection="$1"
          shift 1
          repo="$(git rev-parse --show-toplevel)"
          host="${config.kdn.hostName}"

          args=(
            --phases "disko,install"
            --flake "${kdnConfig.self}#$host"
          )

          ${perVolume (name: value: ''
            addEncryptionKeyArg ${lib.strings.escapeShellArgs [name value.keyFile]}
          '')}

          ${lib.getExe cfg.setup-key-files}

          hostKey="$(runSSH cat /etc/ssh/ssh_host_ed25519_key.pub)
          ageKey="$(ssh-to-age <<<"$hostKey")"

          ensureLineInFile "$repo/.sops.yaml" \
            SSH-KEYS-DEFINITION-INSERT-ABOVE \
            "    $host: {age: [&ssh-$host $ageKey]}"

          ensureLineInFile "$repo/.sops.yaml" \
            SSH-KEYS-USAGE-INSERT-ABOVE \
            "          - *ssh-$host"

          # TODO: add host key with `./known-hosts.sh`
          # TODO: rekey sops files

          nixos-anywhere "''${args[@]}" "$@" "$connection"

          # copy-over SSH keys from the installer itself
          runSSH sudo mkdir -p /mnt/nix/persist/sys/data/etc/ssh
          runSSH sudo cp /etc/ssh/ssh_host_{rsa,ed25519}_key{,.pub} /mnt/nix/persist/sys/data/etc/ssh/

          ${perVolume (name: value: ''
            runSSH sudo systemd-cryptenroll \
              "--unlock-key-file=${value.keyFile}" \
              --wipe-slot=tpm2 --tpm2-device=auto \
              ${lib.strings.escapeShellArg value.header.path}
          '')}
        '';
      };
    };
  };
}
