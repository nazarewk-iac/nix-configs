{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.headless.base;
in {
  options.kdn.headless.base = {
    enable = lib.mkEnableOption "basic headless system configuration";
    debugPolkit = lib.mkEnableOption "polkit debugging";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.sharedModules = [{kdn.headless.base.enable = true;}];}
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
      kdn.programs.handlr.enable = true;
      kdn.programs.nix-utils.enable = true;
      kdn.programs.zsh.enable = true;
      kdn.toolset.fs.enable = true;
      kdn.toolset.fs.encryption.enable = true;
      kdn.toolset.network.enable = true;
      kdn.toolset.unix.enable = true;

      programs.command-not-found.enable = false;

      programs.vim.enable = true;
      programs.vim.defaultEditor = true;
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

      kdn.toolset.essentials.enable = true;

      boot.kernel.sysctl = let
        mb = 1024 * 1024;
      in {
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
      in {
        security.sudo.extraConfig = sudoCfg;
        security.sudo-rs.extraConfig = sudoCfg;
      }
    )
  ]);
}
