{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.headless.base;
  sudoCfg = ''
    Defaults  env_keep += ZELLIJ
    Defaults  env_keep += KDN_ZELLIJ_SKIP
    Defaults  env_keep += TERMINAL_EMULATOR
  '';
in
{
  options.kdn.headless.base = {
    enable = lib.mkEnableOption "basic headless system configuration";
    debugPolkit = lib.mkEnableOption "polkit debugging";

    /*
      The two switches below split one bundle into one concern per switch.

      A developer already owns an editor and a terminal emulator, or objects to this tree's
      choice. So each one gets its own switch.

      Each default is `true`, the value this repository uses today. A `true` default costs nothing
      when `enable` is `false`, because the whole `config` sits behind `enable`. An adopter writes a
      plain `false`, which wins over the `mkDefault` forward into Home Manager.
    */
    vim.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Install vim, and make it the default editor.";
    };
    wezterm.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Write a wezterm key-binding file into the home directory.";
    };
  };

  config = lib.mkMerge [
    # propagate to home-manager
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.headless.base = lib.mkDefault cfg; } ];
    })
    # platform-agnostic kdn.* enables
    # Every line below is `lib.mkDefault`, so an adopter refuses one item with a plain `false`.
    # A plain `= true` sits at priority 100 and collides with a plain `false`, which stops the
    # evaluation. Each value stays the value this repository uses today.
    (lib.mkIf cfg.enable {
      kdn.development.data.enable = lib.mkDefault true;
      kdn.hw.basic.enable = lib.mkDefault true;
      kdn.programs.atuin.enable = lib.mkDefault true;
      kdn.programs.fish.enable = lib.mkDefault true;
      kdn.programs.zellij.enable = lib.mkDefault true;
      kdn.programs.zsh.enable = lib.mkDefault true;
      kdn.toolset.essentials.enable = lib.mkDefault true;
      kdn.toolset.fs.enable = lib.mkDefault true;
      kdn.toolset.fs.encryption.enable = lib.mkDefault true;
      kdn.toolset.network.enable = lib.mkDefault true;
      kdn.toolset.unix.enable = lib.mkDefault true;
      kdn.toolset.nix.enable = lib.mkDefault true;
      # TODO: pulling it in for Helix, move it out into dedicated module
      kdn.toolset.ide.enable = lib.mkDefault true;
      kdn.programs.fish.defaultShell = lib.mkDefault true;
    })
    # home-manager
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          (lib.mkIf cfg.wezterm.enable {
            programs.wezterm.extraConfig = ''
              config.keys = {
                -- Make Backspace send ^? (0x7F) instead of ^H (0x08)
                {
                  key = 'Backspace',
                  action = wezterm.action.SendKey { key = 'Backspace' },
                },
                -- Also fix the Delete key if needed
                {
                  key = 'Delete',
                  action = wezterm.action.SendKey { key = 'Delete' },
                },
              }
            '';
          })
          (lib.mkIf cfg.vim.enable {
            programs.vim.enable = true;
            programs.vim.defaultEditor = lib.mkDefault true;
            programs.vim.extraConfig = ''
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
          })
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
    # nixos + darwin shared
    (kdnConfig.util.ifTypes [ "nixos" "darwin" ] (
      lib.mkIf cfg.enable {
        security.sudo.extraConfig = sudoCfg;
      }
    ))
    (kdnConfig.util.ifTypes [ "darwin" ] (
      lib.mkIf cfg.enable {
      }
    ))
    # nixos
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            boot.kernelParams = [
              "plymouth.enable=0" # disable boot splash screen
            ];

            programs.command-not-found.enable = false;

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

            security.pam.u2f.settings.debug = cfg.debugPolkit;
          }
          {
            security.sudo-rs.extraConfig = sudoCfg;
          }
        ]
      )
    ))
  ];
}
