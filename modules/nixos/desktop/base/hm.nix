{
  osConfig,
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.desktop.base;
  ydotool-paste = pkgs.writeShellApplication {
    name = "ydotool-paste";
    runtimeInputs = with pkgs; [ydotool wl-clipboard];
    text = ''
      sleep "''${1:-0.5}"
      wl-paste --no-newline | ydotool type --file=-
    '';
  };
in {
  options.kdn.desktop.base = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      apply = value: value && config.kdn.desktop.enable;
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.caffeine.enable = true;

      xdg.configFile."wofi/config".source = ./wofi/config;

      home.packages = with pkgs; [
        ydotool-paste

        qalculate-qt
        libqalculate
      ];

      home.sessionPath = ["$HOME/.local/bin"];
      systemd.user.tmpfiles.rules = [
        "d ${config.home.homeDirectory}/.local/bin - - - -"
      ];

      programs.foot.enable = true;
      programs.foot.server.enable = false;
      programs.foot.settings.main.dpi-aware = "no";
      programs.foot.settings.scrollback.lines = 100000;

      programs.wezterm.enable = true;
      programs.wezterm.extraConfig = lib.mkMerge [
        (lib.mkOrder 1 ''config = {}'')
        ''config.front_end = "WebGpu"''
        (lib.mkOrder 9999 ''return config'')
      ];
      #stylix.targets.wezterm.enable = true;
    }
    {
      nixpkgs.overlays = [
        (final: prev: {
          wezterm = prev.wezterm.overrideAttrs {
            patches =
              prev.patches
              or []
              ++ [
                (final.fetchpatch {
                  url = "https://patch-diff.githubusercontent.com/raw/wez/wezterm/pull/6508.patch";
                  sha256 = "sha256-eMpg206tUw8m0Sz+3Ox7HQnejPsWp0VHVw169/Rt4do=";
                })
                .outPath
              ];
          };
        })
      ];
    }
  ]);
}
