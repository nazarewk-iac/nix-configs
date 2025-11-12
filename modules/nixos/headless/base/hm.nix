{
  config,
  lib,
  ...
}: let
  cfg = config.kdn.headless.base;
in {
  options.kdn.headless.base = {
    enable = lib.mkEnableOption "basic headless system configuration";
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.zellij.enable = true;

        programs.zellij.enableFishIntegration = false;
        ## auto-starting zellij gets a little too annyoing in nested sessions
        ## TODO: try also passing `SendEnv` (client) / `AcceptEnv` (server), https://superuser.com/a/702751
        #programs.fish.interactiveShellInit = lib.mkOrder 200 ''
        #  if string match --quiet --ignore-case "jetbrains-*" "$TERMINAL_EMULATOR"
        #    set KDN_ZELLIJ_SKIP "inside jetbrains terminal"
        #  end
        #  if test -n "$KDN_ZELLIJ_SKIP"
        #    echo "zellij skip because: $KDN_ZELLIJ_SKIP" >&2
        #  else
        #    eval (${lib.getExe config.programs.zellij.package} setup --generate-auto-start fish | string collect)
        #  end
        #'';
        kdn.disks.persist."usr/cache".directories = [".cache/zellij"];

        programs.zellij.settings = {
          scroll_buffer_size = 1 * 1000 * 1000;
        };
      }
      (
        let
          xdgAttrs.all =
            (builtins.attrNames config.xdg.userDirs.extraConfig)
            ++ [
              "XDG_DESKTOP_DIR"
              "XDG_DOCUMENTS_DIR"
              "XDG_DOWNLOAD_DIR"
              "XDG_MUSIC_DIR"
              "XDG_PICTURES_DIR"
              "XDG_PUBLICSHARE_DIR"
              "XDG_TEMPLATES_DIR"
              "XDG_VIDEOS_DIR"
            ];
          xdgAttrs.cache = [
            "XDG_DOWNLOAD_DIR"
          ];
          process = dirs:
            lib.pipe dirs [
              (builtins.filter (
                name:
                  (config.home.sessionVariables ? name)
                  && lib.strings.hasPrefix "XDG_" name
                  && lib.strings.hasSuffix "_DIR" name
              ))
              (builtins.map (
                name:
                  lib.strings.removePrefix "${config.home.homeDirectory}/" config.home.sessionVariables."${name}"
              ))
            ];
        in {
          kdn.disks.persist."usr/data".directories = process (
            lib.lists.subtractLists xdgAttrs.cache xdgAttrs.all
          );
          kdn.disks.persist."usr/cache".directories = process xdgAttrs.cache;
        }
      )
    ]
  );
}
