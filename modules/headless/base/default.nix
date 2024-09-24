{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.headless.base;
in
{
  options.kdn.headless.base = {
    enable = lib.mkEnableOption "basic headless system configuration";
    debugPolkit = lib.mkEnableOption "polkit debugging";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # note: about `fish` printing `linux` twice https://github.com/danth/stylix/issues/526
      users.defaultUserShell = pkgs.fish;

      kdn.development.data.enable = true;
      kdn.hardware.basic.enable = true;
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

      environment.systemPackages = with pkgs; [
        openssh
        wget
        curl
        tmux

        # Working with XDG files
        file
        desktop-file-utils
        xdg-utils
        # xdg-launch # this coredumps under KDE, probably poorly written

        # https://wiki.archlinux.org/title/Default%20applications#Resource_openers
        handlr-regex
        mimeo

        jq
        git
        openssl

        coreutils
        moreutils
        gnugrep

        zip

        kdn.whicher
        /* Closure is freaking 9 GB!
              /nix/store/16bffw12fg6jixyal4mn2cknv88rafwg-diffoscope-269
              NAR Size: 2.27 MiB | Closure Size: 8.73 GiB | Added Size: 8.73 GiB
              Immediate Parents: -
        diffoscope
        */
        difftastic
      ];

      boot.kernel.sysctl = let mb = 1024 * 1024; in {
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
        home-manager.sharedModules = [
          (hm: {
            programs.zellij.enable = true;
            xdg.userDirs.enable = true;

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
            #    eval (${lib.getExe hm.config.programs.zellij.package} setup --generate-auto-start fish | string collect)
            #  end
            #'';
            home.persistence."usr/cache".directories = [ ".cache/zellij" ];
          })
        ];
        security.sudo.extraConfig = sudoCfg;
        security.sudo-rs.extraConfig = sudoCfg;
      }
    )
  ]);
}
