{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  options.kdn.profile.machine.baseline = {
    enable = lib.mkEnableOption "baseline machine profile for server/non-interactive use";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.enable = true;
      kdn.locale.enable = true;
      kdn.profile.user.kdn.enable = true;
    }
    {
      kdn.env.packages = with pkgs; [
        git
        bash
        curl

        nix-derivation # pretty-derivation
        nix-output-monitor
        nix-du
        nix-tree
        pkgs.kdn.kdn-nix

        # TODO: remove after resolving https://github.com/sfcompute/hardware_report/issues/22 ?
        (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) kdnConfig.self.inputs.hardware-report.packages."${pkgs.stdenv.hostPlatform.system}".default)
      ];
    }
    (kdnConfig.util.ifTypes ["nixos" "darwin"] (lib.mkMerge [
      {
        kdn.security.secrets.enable = lib.mkDefault true;
        kdn.security.secrets.sops.files."default" = {
          sopsFile = "${kdnConfig.self}/default.unattended.sops.yaml";
        };
        kdn.security.secrets.sops.files."networking" = {
          keyPrefix = "networking";
          sopsFile = "${kdnConfig.self}/default.unattended.sops.yaml";
          basePath = "/run/configs";
          sops.mode = "0444";
        };
      }
      (lib.mkIf config.kdn.security.secrets.allowed {
        sops.templates = lib.pipe config.kdn.security.secrets.sops.placeholders.networking.hosts [
          (lib.attrsets.mapAttrsToList (
            name: text: let
              path = "/etc/hosts.d/60-${config.kdn.managed.infix.default}-${name}.hosts";
            in {
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
    ]))
    {
      kdn.security.secrets.sops.files."anonymization" = {
        keyPrefix = "anonymization";
        sopsFile = "${kdnConfig.self}/default.unattended.sops.yaml";
        basePath = "/run/configs";
        sops.mode = "0444";
      };

      kdn.env.packages = [
        pkgs.kdn.kdn-anonymize
      ];
      kdn.env.variables.KDN_ANONYMIZE_DEFAULTS = "/run/configs";
    }
    (kdnConfig.util.ifTypes ["nixos"] (
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
      in {
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
  ]);
}
