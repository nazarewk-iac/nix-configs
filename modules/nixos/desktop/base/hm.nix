{
  osConfig,
  config,
  pkgs,
  lib,
  kdn,
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
      #services.caffeine.enable = lib.mkDefault true;

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
    }
    {
      programs.wezterm.enable = true;
      programs.wezterm.extraConfig = lib.mkMerge [
        (lib.mkOrder 1 ''config = {}'')
        ''config.front_end = "WebGpu"''
        (lib.mkOrder 9999 ''return config'')
      ];
      nixpkgs.overlays = [
        (final: prev: {
          wezterm = let
            upstream = kdn.inputs.wezterm.packages."${final.stdenv.system}".default;
            base = prev.wezterm;
            #base = upstream;
          in
            base.overrideAttrs {
              patches =
                (prev.patches or [])
                ++ [
                ];
            };
        })
      ];
    }
  ]);
}
