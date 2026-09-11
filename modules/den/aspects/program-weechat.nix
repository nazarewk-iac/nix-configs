# `kdn.programs.weechat`, as a den aspect. It ports `modules/universal/programs/weechat/default.nix`.
#
# Design B applies. The old module writes `kdn.env.packages`; each class writes its own native option.
#
# The old persist write sits behind `hasParentOfAnyType [ "nixos" ]`. That guard tests the parent
# chain and is false on a NixOS host, so the write never fired. This aspect states the real intent and
# routes the directory through `kdn.apps.weechat`.
#
# One honest fix: the aspect names the plugin list. See the comment at `configured` below.
{ kdn, ... }:
let
  declaration =
    { lib, pkgs, ... }:
    {
      options.kdn.programs.weechat.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.weechat;
        description = "The weechat build the aspect configures and installs.";
      };

      options.kdn.programs.weechat.init = lib.mkOption {
        type = lib.types.str;
        apply =
          input:
          lib.trivial.pipe input [
            (lib.strings.splitString "\n")
            (builtins.filter (l: l != "" && !(lib.strings.hasPrefix "#" l)))
            (lib.strings.concatStringsSep "\n")
          ];
        description = ''
          weechat commands the build runs at first start. The `apply` drops a blank line and a comment
          line, so the default below can carry a comment.
        '';
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

      options.kdn.programs.weechat.scripts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs.weechatScripts; [
          # `multiline` is built into weechat from 4.0 on.
          edit
          url_hint
          weechat-autosort
          weechat-go
          weechat-grep
        ];
        description = ''
          Scripts the build carries.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };
    };

  configured =
    cfg:
    cfg.package.override {
      configure =
        { availablePlugins, ... }:
        {
          # The old module names no `plugins`, so the wrapper falls back to every available plugin,
          # and that list holds `php`. The upstream default removes `php` on purpose: it bloats the
          # closure and it does not build on darwin. So the fallback makes the darwin build fail with
          # `attribute 'php' missing`. Measured 2026-09-11 on aarch64-darwin. This line repeats the
          # upstream default and keeps every other plugin.
          plugins = builtins.attrValues (removeAttrs availablePlugins [ "php" ]);
          scripts = cfg.scripts;
          init = cfg.init;
        };
    };

  hostTarget =
    { config, ... }:
    {
      imports = [ declaration ];

      config.environment.systemPackages = [ (configured config.kdn.programs.weechat) ];
    };
in
{
  kdn.program-weechat.includes = [ kdn.apps ];

  kdn.program-weechat.nixos = hostTarget;
  kdn.program-weechat.darwin = hostTarget;

  kdn.program-weechat.homeManager =
    { config, ... }:
    {
      imports = [ declaration ];

      config.home.packages = [ (configured config.kdn.programs.weechat) ];

      config.kdn.apps.weechat = {
        enable = true;
        # `home.packages` above installs the configured build.
        package.install = false;
        dirs.config = [ "weechat" ];
      };
    };
}
