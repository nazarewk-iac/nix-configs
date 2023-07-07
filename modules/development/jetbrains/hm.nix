{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.jetbrains;
in
{
  options.kdn.development.jetbrains = {
    enable = lib.mkEnableOption "Jetbrains tooling";
    go.enable = lib.mkEnableOption "Go specific fixes";
  };

  config = lib.mkIf cfg.enable lib.mkMerge [
    {
      programs.fish.shellInit = ''
        export PATH="$PATH:$HOME/.local/share/JetBrains/Toolbox/scripts"
      '';

      home.packages = with pkgs; [
        #jetbrains.pycharm-professional
        jetbrains.idea-ultimate
        jetbrains-toolbox
        #jetbrains.jdk
        jetbrains.gateway
        #jetbrains.clion
        #jetbrains.goland
        #jetbrains.ruby-mine
      ];
      systemd.user.services.jetbrains-remote = {
        Unit.Description = ''Automatically fix the IDEA Ultimate used by the remote SSH extension, based on https://github.com/NixOS/nixpkgs/issues/153335#issuecomment-1139366573'';
        Service.Restart = "always";
        Service.RestartSec = 0;
        Service.ExecStart = pkgs.writeShellScript "jetbrains-remote.sh" ''
          set -eEuo pipefail
          PATH=${lib.makeBinPath (with pkgs; [ coreutils findutils inotify-tools patchelf gnused ])}
          bin_dir="$HOME/.cache/JetBrains/RemoteDev/dist"

          mkdir -p "$bin_dir"

          get_file_size() {
            fname="$1"
            echo $(ls -l $fname | cut -d ' ' -f5)
          }
          munge_size_hack() {
            fname="$1"
            size="$2"
            strip $fname
            truncate --size=$size $fname
          }

          patch_fs_notifier() {
            interpreter=$(echo ${pkgs.glibc.out}/lib/ld-linux*.so.2)
            fs_notifier=$1;

            if [ -z "$in" ]; then
              read fs_notifier;
            fi

            target_size=$(get_file_size $fs_notifier)
            patchelf --set-interpreter "$interpreter" $fs_notifier
            munge_size_hack $fs_notifier $target_size
          }

          find "$bin_dir/" -mindepth 5 -maxdepth 5 -name launcher.sh -exec sed -i -e 's#exec /lib64/ld-linux-x86-64.so.2#exec ${pkgs.glibc.out}/lib/ld-linux-x86-64.so.2#g' {} \;
          find "$bin_dir/" -mindepth 3 -maxdepth 3 -name fsnotifier -exec patch_fs_notifier {} \;
          find "$bin_dir/" -mindepth 3 -maxdepth 3 -name fsnotifier64 -exec patch_fs_notifier {} \;

          while IFS=: read -r out event; do
            case "$out" in
              */remote-dev-server/bin)
                sed -i 's#exec /lib64/ld-linux-x86-64.so.2#exec ${pkgs.glibc.out}/lib/ld-linux-x86-64.so.2#g' "$out/launcher.sh"

                if [[ "${pkgs.stdenv.hostPlatform.system}" == "x86_64-linux" && -e $out/fsnotifier64 ]]; then
                  patch_fs_notifier $out/fsnotifier64
                else
                  patch_fs_notifier $out/fsnotifier
                fi
              ;;
            esac
          done < <(inotifywait -r -m -q -e CREATE --include '^.*ideaIU[-[:digit:]\.]+(/plugins)?(/remote-dev-server)?(/bin)?$' --format '%w%f:%e' "$bin_dir/")
        '';
        Install.WantedBy = [ "default.target" ];
      };
    }
    (lib.mkIf cfg.go.enable (
      let
        cmd = ''
          if [ -d '${config.xdg.dataHome}/Jetbrains' ] ; then
            for ide in ${config.xdg.dataHome}/Jetbrains/* ; do
              mkdir -p "$ide/go/lib/dlv/linux"
              ln -sf "${pkgs.delve}/bin/dlv" "$ide/go/lib/dlv/linux/dlv"
            done
          fi
        '';
      in
      {
        programs.bash.profileExtra = cmd;
        programs.zsh.profileExtra = cmd;
        programs.fish.shellInit = cmd;
      }
    ))
  ];
}
