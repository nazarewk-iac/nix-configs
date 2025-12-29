{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];
  config = lib.mkMerge [
    {
      kdn.hostName = "anji-linux-builder";
      system.stateVersion = "24.05"; # set by the nix-builder-vm.nix
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "776e4154"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.remote-builders.enable = true;
      kdn.nix.remote-builder.localhost.maxJobs = 4;
      kdn.nix.remote-builder.localhost.speedFactor = 8;
    }
    {
      kdn.profile.user.kdn.enable = true;
      security.sudo.wheelNeedsPassword = false;
      services.getty.autologinUser = lib.mkForce "kdn";
    }
    {
      systemd.services."kdn-ensure-ssh-host-key" = {
        description = "clears hardcoded linux builder's ssh host keys and puts it in a shared folder";
        before = [
          "sops-install-secrets.service"
          "sshd-keygen.service"
          "sshd.service"
        ];
        wantedBy = [
          "sops-install-secrets.service"
          "sshd-keygen.service"
          "sshd.service"
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = let
            script = pkgs.writeShellApplication {
              name = "kdn-ensure-ssh-host-key";
              runtimeInputs = with pkgs; [
                diffutils
                openssh
              ];
              text = ''
                set -xeEuo pipefail

                KEYS_DIR=/etc/ssh
                # see https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/profiles/nix-builder-vm.nix#L17
                SHARED_KEYS_DIR=/var/keys

                for shared in "$SHARED_KEYS_DIR"/ssh_host_*_key{,.pub} ; do
                  file="''${shared##*/}"
                  target="$KEYS_DIR/$file"
                  if cmp -s "$target" "$shared" ; then
                    echo "keys are the same: shared=$shared target=$target"
                    continue
                  fi
                  echo "keys differ: shared=$shared target=$target"
                  rm -f "$target"
                  cp -a "$shared" "$target"
                done
                chmod 0400 "$KEYS_DIR"/ssh_host_*_key
              '';
            };
          in
            lib.getExe script;
        };
      };
    }
  ];
}
