# The `profile/machine/basic` module of the old tree, as one den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# `profile-basic` is the bundle for an interactive machine. It reaches `profile-baseline`, and it
# adds flatpak, appimage, a USB modem switch, a runtime man-page cache and the WLAN profiles.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module holds `lsix` outside every context guard, so all three classes carry a package.
# The `nixos` class carries the rest.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The three `enable` writes become `includes` entries.**
# 3. **`boot-debug.enable` goes.** `grep -rn boot-debug modules/ hosts/` finds the declaration at
#    `basic/default.nix:14` and **no reader**. The three `specialisation.boot-debug` hits sit in the
#    baseline module and read `config.boot.initrd.systemd.enable` instead. So the option is dead.
# 4. **The WLAN list becomes an option.** `basic/default.nix:92-97` names four real networks and
#    their priorities, and `:113` reads the secret tree of another aspect. The port declares
#    `kdn.profile-basic.wlan`, an `attrsOf submodule` with default `{ }`. A network name is
#    personal, so the consumer supplies the value. The default `{ }` keeps the whole block inert,
#    and `checks/standalone.nix:207-209` allows an `enable` inside an `attrsOf submodule` — this
#    submodule declares none anyway.
# 5. **`kdn.env.packages` goes.** Each target writes the native package option of its own class.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.** See changes 1, 3 and 4.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.profile-basic.wlan = lib.mkOption {
        default = { };
        description = ''
          The wireless networks this machine joins, keyed by network name.

          The old module holds a literal list of four real networks. A network name is personal, so
          the consumer names its own. An empty set writes no profile at all.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options.ssid = lib.mkOption {
                type = lib.types.str;
                default = name;
                defaultText = lib.literalExpression "the attribute name";
                description = "The network name on the air. It defaults to the attribute name.";
              };
              options.priority = lib.mkOption {
                type = with lib.types; nullOr int;
                default = null;
                example = 50;
                description = ''
                  The auto-connect priority. `null` turns auto-connect off for this network, which
                  is what the old module does for a network absent from its priority list.
                '';
              };
              options.passwordFile = lib.mkOption {
                type = lib.types.path;
                description = ''
                  A file that holds the pre-shared key of this network. A password never belongs in
                  a module file, so the consumer names a secret file.
                '';
              };
            }
          )
        );
      };
    };
in
{
  kdn.profile-basic.includes = [
    kdn.hw-bluetooth
    kdn.profile-baseline
    kdn.program-gnupg
  ];

  kdn.profile-basic.darwin =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      # `lsix` shows an image thumbnail in the terminal.
      config.environment.systemPackages = import ../common/filter-packages.nix { inherit lib; } [
        pkgs.lsix
      ];
    };

  kdn.profile-basic.homeManager =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      config.home.packages = import ../common/filter-packages.nix { inherit lib; } [ pkgs.lsix ];
    };

  kdn.profile-basic.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.profile-basic;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      kdn-man-gen-caches = pkgs.writeShellApplication {
        name = "kdn-man-gen-caches";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [[ $EUID -ne 0 ]]; then
            echo "restarting as root..." >&2
            exec sudo "$BASH" "$0" "$@"
          fi

          mkdir -p /var/cache/man/nixos
          ${lib.getExe' config.documentation.man.man-db.package "mandb"} "$@"
        '';
      };

      envPath = "/etc/NetworkManager/system-connections/default.unattended.sops.env";

      # One entry per network. `safeSSID` becomes part of a shell variable name, so it drops every
      # character a shell rejects.
      wlanEntries = lib.mapAttrs (
        _: wlan:
        let
          safeSSID = lib.pipe wlan.ssid [
            lib.strings.toLower
            (lib.strings.replaceStrings [ "-" ] [ "_" ])
          ];
        in
        {
          inherit (wlan) ssid priority passwordFile;
          inherit safeSSID;
          envKey = "wifi_password_${safeSSID}";
        }
      ) cfg.wlan;
    in
    {
      imports = [
        declaration
        ../common/persist.nix
      ];

      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages [
            pkgs.lsix
            pkgs.usb-modeswitch
            kdn-man-gen-caches
          ];

          networking.networkmanager.wifi.powersave = lib.mkDefault true;
          boot.loader.systemd-boot.memtest86.enable = lib.mkDefault true;
          hardware.usb-modeswitch.enable = lib.mkDefault true;
        }
        {
          services.flatpak.enable = lib.mkDefault true;
          systemd.services.flatpak-repo = {
            wantedBy = [ "multi-user.target" ];
            path = [ config.services.flatpak.package ];
            script = ''
              flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            '';
          };
        }
        {
          programs.appimage.enable = lib.mkDefault true;
          programs.appimage.binfmt = lib.mkDefault true;
        }
        {
          # The man-page cache is built at run time, not at build time. So a rebuild stays fast.
          kdn.disks.persist."sys/cache".directories = [
            "/var/cache/man/nixos"
          ];
          systemd.services.kdn-man-gen-caches = {
            wantedBy = [ "multi-user.target" ];
            description = "generates manpage caches during runtime instead of during build";
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;
            serviceConfig.ExecStart = lib.strings.escapeShellArgs [
              (lib.getExe kdn-man-gen-caches)
            ];
          };
          system.activationScripts.kdn-man-gen-caches.deps = [ "etc" ];
          system.activationScripts.kdn-man-gen-caches.text = ''
            ${lib.getExe' pkgs.systemd "systemctl"} start --no-block kdn-man-gen-caches.service
          '';
        }
        (lib.mkIf (wlanEntries != { }) {
          systemd.services.kdn-networkmanager-gen-secrets-environments = {
            description = "Renders NetworkManager environment for secrets";
            after = [ "kdn-secrets.target" ];
            requires = [ "kdn-secrets.target" ];
            partOf = [ "kdn-secrets-reload.target" ];
            serviceConfig.Type = "oneshot";
            serviceConfig.ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "kdn-networkmanager-gen-secrets-environments";
                runtimeInputs = with pkgs; [
                  coreutils
                  gnused
                ];
                runtimeEnv.ENV_PATH = envPath;
                text =
                  let
                    # A systemd `EnvironmentFile` value keeps its content only when the line
                    # double-quotes it and escapes `$`, `"` and a backtick with a backslash.
                    wifiPasswords = lib.pipe wlanEntries [
                      (lib.attrsets.mapAttrsToList (
                        _: wlan: ''
                          printf '%s="%s"\n' ${wlan.envKey} "$(sed -e 's/\(["\\`$]\)/\\\1/g' <${lib.strings.escapeShellArg wlan.passwordFile})"
                        ''
                      ))
                      (builtins.concatStringsSep "\n")
                    ];
                  in
                  ''
                    mkdir -p "''${ENV_PATH%/*}"
                    touch "$ENV_PATH"
                    chmod 0600 "$ENV_PATH"
                    (
                      ${wifiPasswords}
                    ) >"$ENV_PATH"
                  '';
              }
            );
          };
          systemd.services.NetworkManager-ensure-profiles = {
            requires = [ "kdn-networkmanager-gen-secrets-environments.service" ];
            after = [ "kdn-networkmanager-gen-secrets-environments.service" ];
            serviceConfig.EnvironmentFile = [ envPath ];
          };
          networking.networkmanager.ensureProfiles.profiles = lib.pipe wlanEntries [
            (lib.attrsets.mapAttrs' (
              _: wlan: {
                name = "wifi-${lib.strings.replaceStrings [ "_" ] [ "-" ] wlan.safeSSID}";
                value = {
                  connection.id = wlan.ssid;
                  connection.type = "wifi";
                  connection.autoconnect = wlan.priority != null;
                  connection.autoconnect-priority = if wlan.priority == null then 0 else wlan.priority;
                  wifi.mode = "infrastructure";
                  wifi.ssid = wlan.ssid;
                  wifi-security.key-mgmt = "wpa-psk";
                  wifi-security.psk = "\${${wlan.envKey}}";
                  ipv4.method = "auto";
                  ipv6.method = "auto";
                  ipv6.addr-gen-mode = "stable-privacy";
                };
              }
            ))
          ];
        })
      ];
    };
}
