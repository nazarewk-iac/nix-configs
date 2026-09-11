{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.profile.default-secrets;
in
{
  options.kdn.profile.default-secrets = {
    enable = lib.mkEnableOption "baseline machine profile for server/non-interactive use";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # This profile owns the personal literal. The engine option holds no path, so an adopter
        # that keeps the profile still names its own file.
        kdn.security.secrets.sops.defaultFile =
          lib.mkDefault "${kdnConfig.self}/default.unattended.sops.yaml";
        # The discovery engine calls `builtins.readFile` on that file, and an absent path stops the
        # whole evaluation. So the switch follows the presence of the file. A consumer with no file
        # then reaches the state 008 calls mode A, and it needs no second setting.
        kdn.security.secrets.enable = lib.mkDefault config.kdn.security.secrets.sops.hasDefaultFile;
        # `sopsFile` is `types.path`, so a `null` value is a type error. Declare no entry at all
        # when the file is absent.
        kdn.security.secrets.sops.files = lib.mkIf config.kdn.security.secrets.sops.hasDefaultFile {
          "default" = {
            sopsFile = config.kdn.security.secrets.sops.defaultFile;
          };
          "networking" = {
            keyPrefix = "networking";
            sopsFile = config.kdn.security.secrets.sops.defaultFile;
            basePath = "/run/configs";
            sops.mode = "0444";
          };
        };
      }
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] (
        lib.mkMerge [
          (lib.mkIf config.kdn.security.secrets.allowed {
            sops.templates = lib.pipe config.kdn.security.secrets.sops.placeholders.networking.hosts [
              (lib.attrsets.mapAttrsToList (
                name: text:
                let
                  path = "/etc/hosts.d/60-${config.kdn.managed.infix.default}-${name}.hosts";
                in
                {
                  "${path}" = {
                    inherit path;
                    mode = "0644";
                    content = text;
                  };
                }
              ))
              (
                l:
                l
                ++ [
                  {
                    # TODO: render those from "$XDG_CONFIG_DIRS/nix/access-tokens.d/*.tokens" for both users and system-wide?
                    "nix.access-tokens.auto.conf" = {
                      path = "/etc/nix/nix.access-tokens.auto.conf";
                      mode = "0444";
                      content = lib.pipe config.kdn.security.secrets.sops.placeholders.default.nix.access-tokens [
                        (lib.attrsets.mapAttrsToList (name: value: "${name}=${value}"))
                        (builtins.concatStringsSep " ")
                        (value: ''
                          access-tokens = ${value}
                        '')
                      ];
                    };
                  }
                ]
              )
              lib.mkMerge
            ];
          })
          {
            kdn.env.packages = [
              (pkgs.writeShellApplication {
                name = "kdn-net-anonymize";
                text = ''
                  ${lib.getExe pkgs.kdn.kdn-anonymize} /run/configs/networking/anonymization
                '';
              })
            ];
          }
        ]
      ))
      {
        kdn.security.secrets.sops.files = lib.mkIf config.kdn.security.secrets.sops.hasDefaultFile {
          "anonymization" = {
            keyPrefix = "anonymization";
            sopsFile = config.kdn.security.secrets.sops.defaultFile;
            basePath = "/run/configs";
            sops.mode = "0444";
          };
        };

        kdn.env.packages = [
          pkgs.kdn.kdn-anonymize
        ];
        kdn.env.variables.KDN_ANONYMIZE_DEFAULTS = "/run/configs";
      }
      (kdnConfig.util.ifTypes [ "nixos" ] (
        let
          anonymizeClipboard = pkgs.writeShellApplication {
            name = "kdn-anonymize-clipboard";
            runtimeInputs = with pkgs; [
              pkgs.kdn.kdn-anonymize
              wl-clipboard
              libnotify
            ];
            text = ''
              # see https://github.com/bugaevc/wl-clipboard/issues/245
              notify-send --expire-time=3000 "kdn-anonymize-clipboard" "$( { wl-paste | kdn-anonymize | wl-copy 2>/dev/null ; } 2>&1 )"
            '';
          };
        in
        {
          kdn.env.packages = lib.lists.optional config.kdn.desktop.enable anonymizeClipboard;
          home-manager.sharedModules = [
            {
              wayland.windowManager.sway = {
                config.keybindings = with config.kdn.desktop.sway.keys; {
                  "${ctrl}+${super}+A" = "exec '${lib.getExe anonymizeClipboard}'";
                };
              };
            }
          ];
        }
      ))
    ]
  );
}
