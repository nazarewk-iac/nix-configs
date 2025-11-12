{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.weechat;
in {
  options.kdn.programs.weechat = {
    enable = lib.mkEnableOption "weechat setup";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.weechat;
    };

    init = lib.mkOption {
      type = lib.types.str;
      apply = input:
        lib.trivial.pipe input [
          (lib.strings.splitString "\n")
          (builtins.filter (l: l != "" && !(lib.strings.hasPrefix "#" l)))
          (lib.strings.concatStringsSep "\n")
        ];

      default = ''
        # see https://xeiaso.net/blog/irc-stuff-nixos-2021-05-29
        /set irc.look.server_buffer independent
        /mouse enable
        /set script.scripts.download_enabled on
        /script install confversion.py
        /key bind meta-j /go

        /script install listbuffer.py
        /script install screen_away.py
        /script install colorize_nicks.py
        /script install histman.py
        /script install histsearch.py

        /key bind meta-s /input return
        # this fixes multiline priority
        /key unbind ctrl-m

        /server add libera  irc.libera.chat/6697 -tls -autoconnect
        /server add oftc    irc.oftc.net/6697 -ssl -autoconnect
        /server add gimp    irc.gimp.org/6697 -ssl -autoconnect
        /set irc.server_default.autojoin_dynamic on

      '';
    };

    scripts = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs.weechatScripts; [
        # multiline # already built into weechat from 4.0+
        edit
        url_hint
        weechat-autosort
        weechat-go
        weechat-grep
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (cfg.package.override {
        configure = {availablePlugins, ...}: {
          scripts = cfg.scripts;
          init = cfg.init;
        };
      })
    ];
    kdn.disks.persist."usr/config".directories = [
      ".config/weechat"
    ];
  };
}
