{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.headless.base;
in {
  options.nazarewk.headless.base = {
    enable = mkEnableOption "basic headless system configuration";
  };

  config = mkIf cfg.enable {
    nazarewk.filesystems.base.enable = true;

    programs.xonsh.enable = true;
    programs.zsh.enable = true;
    users.defaultUserShell = pkgs.zsh;
    programs.zsh.interactiveShellInit = ''
      source ${pkgs.grml-zsh-config}/etc/zsh/zshrc
    '';
    programs.zsh.promptInit = ""; # otherwise it'll override the grml prompt
    programs.zsh.syntaxHighlighting.enable = true;
    programs.zsh.histSize = 100000;

    programs.command-not-found.enable = false;
    programs.bash.interactiveShellInit = ''
    '';

    programs.vim.defaultEditor = true;
    programs.vim.package = pkgs.vim_configurable.customize {
      name = "vim";
      vimrcConfig.customRC = ''
        syntax on
        set number	" Show line numbers
        set linebreak	" Break lines at word (requires Wrap lines)
        set showbreak=+++ 	" Wrap-broken line prefix
        set textwidth=100	" Line wrap (number of cols)
        set showmatch	" Highlight matching brace
        set visualbell	" Use visual bell (no beeping)

        set hlsearch	" Highlight all search results
        set smartcase	" Enable smart-case search
        set ignorecase	" Always case-insensitive
        set incsearch	" Searches for strings incrementally

        set autoindent	" Auto-indent new lines
        set expandtab	" Use spaces instead of tabs
        set shiftwidth=4	" Number of auto-indent spaces
        set smartindent	" Enable smart-indent
        set smarttab	" Enable smart-tabs
        set softtabstop=4	" Number of spaces per Tab

        set ruler	" Show row and column ruler information

        set undolevels=1000	" Number of undo levels
        set backspace=indent,eol,start	" Backspace behaviour
      '';
    };

    environment.systemPackages = with pkgs; [
      openssh
      wget
      curl
      pstree
      xdg-utils
      tmux

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

      glxinfo
      inxi

      inotify-tools
      jq
      git
      dig
      cryptsetup
      file

      coreutils
      gnugrep
    ];
  };
}