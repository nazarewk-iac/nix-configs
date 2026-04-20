{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.headless.base;
in
{
  options.kdn.headless.base = {
    enable = lib.mkEnableOption "basic headless system configuration";
    debugPolkit = lib.mkEnableOption "polkit debugging";
  };

  config = lib.mkMerge [
    # home-manager
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
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
            kdn.disks.persist."usr/cache".directories = [ ".cache/zellij" ];
            programs.zellij.settings.scroll_buffer_size = 1 * 1000 * 1000;

            # TODO: this is "temporary" measure to use built-in theme instead of stylix
            programs.zellij.settings.theme = "dracula";
            # an example to customize the stylix theme
            programs.zellij.themes.stylix.default = with config.lib.stylix.colors.withHashtag; {
              ## TODO: this is not the right color to override in stylix theme (barely legible green text on grey background on the ribbon)
              # ribbon_unselected.background = "#${base01}";
            };
          }
          (
            let
              xdgAttrs.all = (builtins.attrNames config.xdg.userDirs.extraConfig) ++ [
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
              process =
                dirs:
                lib.pipe dirs [
                  (builtins.filter (
                    name:
                    (config.home.sessionVariables ? name)
                    && lib.strings.hasPrefix "XDG_" name
                    && lib.strings.hasSuffix "_DIR" name
                  ))
                  (map (
                    name:
                    lib.strings.removePrefix "${config.home.homeDirectory}/" config.home.sessionVariables."${name}"
                  ))
                ];
            in
            {
              kdn.disks.persist."usr/data".directories = process (
                lib.lists.subtractLists xdgAttrs.cache xdgAttrs.all
              );
              kdn.disks.persist."usr/cache".directories = process xdgAttrs.cache;
            }
          )
        ]
      )
    ))
    # nixos
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          { home-manager.sharedModules = [ { kdn.headless.base.enable = true; } ]; }
          {
            boot.kernelParams = [
              "plymouth.enable=0" # disable boot splash screen
            ];
            # note: about `fish` printing `linux` twice https://github.com/danth/stylix/issues/526
            users.defaultUserShell = pkgs.fish;

            kdn.development.data.enable = true;
            kdn.hw.basic.enable = true;
            kdn.programs.atuin.enable = true;
            kdn.programs.fish.enable = true;
            kdn.programs.zsh.enable = true;
            kdn.toolset.essentials.enable = true;
            kdn.toolset.fs.enable = true;
            kdn.toolset.fs.encryption.enable = true;
            kdn.toolset.network.enable = true;
            kdn.toolset.unix.enable = true;
            kdn.toolset.nix.enable = true;

            programs.command-not-found.enable = false;

            kdn.toolset.ide.enable = true; # TODO: pulling it in for Helix, move it out into dedicated module
            programs.vim.enable = true;
            programs.vim.defaultEditor = lib.mkDefault true;
            programs.vim.package = pkgs.vim-full.customize {
              name = "vim";
              vimrcConfig.customRC = ''
                syntax on
                set number  " Show line numbers
                set linebreak  " Break lines at word (requires Wrap lines)
                set showbreak=+++   " Wrap-broken line prefix
                set textwidth=100  " Line wrap (number of cols)
                set showmatch  " Highlight matching brace
                set visualbell  " Use visual bell (no beeping)

                set hlsearch  " Highlight all search results
                set smartcase  " Enable smart-case search
                set ignorecase  " Always case-insensitive
                set incsearch  " Searches for strings incrementally

                set autoindent  " Auto-indent new lines
                set expandtab  " Use spaces instead of tabs
                set shiftwidth=4  " Number of auto-indent spaces
                "set smartindent  " Enable smart-indent
                "set smarttab  " Enable smart-tabs
                set softtabstop=4  " Number of spaces per Tab

                set ruler  " Show row and column ruler information

                set undolevels=1000  " Number of undo levels
                set backspace=indent,eol,start  " Backspace behaviour
              '';
            };

            environment.localBinInPath = true;

            boot.kernel.sysctl =
              let
                mb = 1024 * 1024;
              in
              {
                # https://wiki.archlinux.org/title/Sysctl#Virtual_memory
                "vm.dirty_background_bytes" = 4 * mb;
                "vm.dirty_bytes" = 4 * mb;

                "vm.vfs_cache_pressure" = 50;

                "fs.inotify.max_user_watches" = 1048576; # default:  8192
                "fs.inotify.max_user_instances" = 1024; # default:   128
                "fs.inotify.max_queued_events" = 32768; # default: 16384
              };

            # `dbus` seems to be bugged when combined with DynamicUser services
            services.dbus.implementation = "broker";
          }
          {
            security.polkit.enable = true;

            security.polkit.debug = cfg.debugPolkit;
            security.pam.u2f.settings.debug = cfg.debugPolkit;
          }
          (
            let
              sudoCfg = ''
                Defaults  env_keep += ZELLIJ
                Defaults  env_keep += KDN_ZELLIJ_SKIP
                Defaults  env_keep += TERMINAL_EMULATOR
              '';
            in
            {
              security.sudo.extraConfig = sudoCfg;
              security.sudo-rs.extraConfig = sudoCfg;
            }
          )
        ]
      )
    ))
  ]; # end config mkMerge
}
