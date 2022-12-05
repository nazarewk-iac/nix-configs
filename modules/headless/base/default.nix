{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.headless.base;
in
{
  options.kdn.headless.base = {
    enable = lib.mkEnableOption "basic headless system configuration";
  };

  config = mkIf cfg.enable {
    kdn.development.data.enable = true;
    kdn.filesystems.base.enable = true;
    kdn.development.linux-utils.enable = true;

    users.defaultUserShell = pkgs.zsh;
    kdn.programs.zsh.enable = true;

    programs.command-not-found.enable = false;
    programs.bash.interactiveShellInit = ''
    '';

    programs.vim.defaultEditor = true;
    programs.vim.package = pkgs.vim_configurable.customize {
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
        set smartindent  " Enable smart-indent
        set smarttab  " Enable smart-tabs
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
      pstree
      tmux

      # Working with XDG files
      desktop-file-utils
      xdg-utils
      xdg-launch

      # https://wiki.archlinux.org/title/Default%20applications#Resource_openers
      handlr
      mimeo

      zsh-completions
      nix-zsh-completions

      killall
      ncdu
      htop
      bintools

      usbutils
      lshw
      lsof
      pciutils
      dmidecode

      glxinfo
      inxi

      inotify-tools
      jq
      git
      dig
      cryptsetup
      file
      tree
      openssl

      coreutils
      moreutils
      gnugrep

      zip
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
  };
}
