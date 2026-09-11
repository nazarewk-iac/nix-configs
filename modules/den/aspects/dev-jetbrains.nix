# The `development/jetbrains` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs two JetBrains integrated development environments, puts the Toolbox scripts directory
# on the fish path, and runs a user service that patches the remote development server the IDE
# downloads at run time. With `go.use` on, it also links the Nix `dlv` over the copy the Go plugin
# downloads.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`go.enable` becomes `kdn.dev-jetbrains.go.use`.** den declares no reachable `enable`, and the
#    default stays `false`.
# 3. **The desktop assertion goes.** The old module asserts `config.kdn.desktop.enable`, an option of
#    another area. A consumer that wants a desktop names the desktop aspect too.
# 4. **`kdn.env.packages` goes.** The target writes `home.packages`, through
#    ../common/filter-packages.nix. Design B.
# 5. **The four persist paths become a read-only option.** The old module writes
#    `kdn.disks.persist.*`, which another area declares. This aspect publishes
#    `kdn.dev-persist.dev-jetbrains` and the consumer wires it.
# 6. **The systemd parts take a Linux guard.** The service reads `pkgs.glibc` and `inotify-tools`,
#    and `systemd.user.tmpfiles` asserts a Linux platform. A Darwin Home Manager evaluation fails
#    without the guard. Linux behaviour does not change.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-jetbrains.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.dev-jetbrains;
    in
    {
      options.kdn.dev-jetbrains.go.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Link the Nix `dlv` debugger over the copy the JetBrains Go plugin downloads.

          The plugin ships a `dlv` build that a Nix system cannot run. The shell profile links the
          Nix build over each copy it finds.
        '';
      };

      options.kdn.dev-persist.dev-jetbrains = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
        default = {
          "usr/data".directories = [ ".local/share/JetBrains" ];
          "usr/cache".directories = [ ".cache/JetBrains" ];
          "usr/config".directories = [ ".config/JetBrains" ];
          "usr/state".directories = [ ".java/.userPrefs/jetbrains" ];
          # The IDE writes the `JetBrains.UserIdOnMachine` property to this file.
          "usr/state".files = [ ".java/.userPrefs/prefs.xml" ];
        };
        description = ''
          The paths this aspect keeps across a wipe, in the shape the persist area takes.

          This aspect writes no persist option of its own. A consumer collects every
          `kdn.dev-persist.*` value and wires it in one line.
        '';
      };

      config = lib.mkMerge [
        {
          programs.fish.shellInit = ''
            fish_add_path --append --move "$HOME/.local/share/JetBrains/Toolbox/scripts"
          '';

          # To see the main toolbar under Wayland, clear this setting:
          # Settings > Appearance & Behavior > Appearance > UI Options:
          #   Merge main menu with window title
          # See https://youtrack.jetbrains.com/issue/IDEA-323700
          home.packages = import ../common/filter-packages.nix { inherit lib; } (
            with pkgs;
            [
              #jetbrains.pycharm-professional
              jetbrains.idea
              #jetbrains.idea-ultimate-eap
              #jetbrains-toolbox
              #jetbrains.jdk
              #jetbrains.gateway
              jetbrains.clion
              #jetbrains.goland
              #jetbrains.ruby-mine

              # CPython needs a compiler. `hiPrio` settles the conflict with `binutils`.
              (lib.hiPrio gcc)
            ]
          );
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          systemd.user.services.jetbrains-remote = {
            Unit.Description = "It fixes the IDEA Ultimate build that the remote SSH extension downloads. Based on https://github.com/NixOS/nixpkgs/issues/153335#issuecomment-1139366573";
            Service.Restart = "always";
            Service.RestartSec = 0;
            Service.ExecStart = pkgs.writeShellScript "jetbrains-remote.sh" ''
              set -eEuo pipefail
              PATH=${
                lib.makeBinPath (
                  with pkgs;
                  [
                    coreutils
                    findutils
                    inotify-tools
                    patchelf
                    gnused
                  ]
                )
              }
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

          systemd.user.tmpfiles.rules = [
            "L %h/.local/bin/pkexec - - - - /run/wrappers/bin/sudo"
          ];
        })
        (lib.mkIf cfg.go.use (
          let
            name = "symlink-jetbrains-delve";
            pkg = pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = with pkgs; [ ];
              text = ''
                shopt -s nocaseglob # the JetBrains folder name is not always the same
                shopt -s globstar
                shopt -s nullglob

                # TODO: the path could be dlv/{linux,linuxarm,mac,macarm}/dlv, but a wider glob does
                # no harm for local use.
                for dlv in "$XDG_DATA_HOME"/JetBrains/**/dlv/*/dlv ; do
                  ln -sf "${pkgs.delve}/bin/dlv" "$dlv"
                done
              '';
            };
            bin = "${pkg}/bin/${name}";
          in
          {
            programs.bash.profileExtra = bin;
            programs.zsh.profileExtra = bin;
            programs.fish.shellInit = bin;
          }
        ))
      ];
    };
}
