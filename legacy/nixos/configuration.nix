# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
#
# see https://gist.github.com/dysinger/2a768db5b6e3b729ec898d7d4208add3

{ config, pkgs, lib, ... }:
{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./nazarewk.nix
  ];

  # NIX / NIXOS
  # renamed from nix.autoOptimiseStore
  nix.settings.auto-optimise-store = true;
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "21.05";
  location.provider = "geoclue2";

  # BOOT
  boot.kernelParams = [ "consoleblank=90" ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "wasm32-wasi"
    "wasm64-wasi"
    "x86_64-windows"
  ];
  boot.cleanTmpDir = true;

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576; # default:  8192
    "fs.inotify.max_user_instances" = 1024; # default:   128
    "fs.inotify.max_queued_events" = 32768; # default: 16384
  };

  # HARDWARE
  services.cpupower-gui.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  hardware.opengl.driSupport32Bit = true;
  hardware.sane.enable = true;
  hardware.video.hidpi.enable = true;


  # NETWORKING
  networking.hostId = "f77614af"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "nazarewk";
  networking.nameservers = [
    "2606:4700:4700::1111" # CloudFlare
    "1.1.1.1" # CloudFlare
    "8.8.8.8" # Google
  ];
  networking.firewall.enable = true;
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  # LOCALE
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "en_GB.UTF-8"; # en_GB - Monday as first day of week
  };
  time.timeZone = "Europe/Warsaw";

  # INPUT
  services.xserver.layout = "pl";
  console.useXkbConfig = true;
  services.xserver.libinput.enable = true;
  services.xserver.libinput.touchpad.disableWhileTyping = true;
  services.xserver.libinput.touchpad.naturalScrolling = true;
  services.xserver.libinput.touchpad.tapping = true;
  services.xserver.synaptics.twoFingerScroll = true;

  # SSH
  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  # ANDROID
  programs.adb.enable = true;

  # KEYBASE
  services.kbfs.enable = true;
  services.davfs2.enable = true;

  # virtualization
  virtualisation.docker.enable = false;
  virtualisation.docker.autoPrune.enable = false;
  virtualisation.libvirtd.enable = true;

  # USERS
  users.users.root.initialHashedPassword = "";

  # FIXES
  # need to run nixos-install with extra-sandbox-paths '/bin/sh=...', see https://github.com/NixOS/nixpkgs/issues/124215#issuecomment-848305838

  # CUSTOM

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [
    hplip
    gutenprint
    gutenprintBin
    brlaser
    brgenml1lpr
    brgenml1cupswrapper
  ];
  services.avahi.enable = true;

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

  programs.seahorse.enable = true;

  fonts.fonts = with pkgs; [
    cantarell-fonts
    font-awesome
    nerdfonts
    noto-fonts
    noto-fonts-emoji
    noto-fonts-emoji-blob-bin
    noto-fonts-extra
  ];

  programs.java.enable = true;
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
    wget
    curl
    pstree
    xdg-utils

    zsh-completions
    nix-zsh-completions

    usbutils
    lshw
    glxinfo
    inxi

    dex
    firefox-wayland
    chromium
    google-chrome
    jetbrains.pycharm-professional
    jetbrains.idea-ultimate
    p7zip
    nix-tree
    nix-du
    nixfmt
    nixpkgs-fmt
    system-config-printer

    ntfs3g
    gptfdisk
    gparted
    tmux

    # networking
    dnsmasq
    iw

    killall
    inotify-tools
    bintools
    mc
    htop
    pciutils
    ncdu
    jq
    lsof
    git
    dig
    cryptsetup
    qrcode
    libqrencode
    imagemagick
    #((pkgs.gradleGen.override { java = jdk; }).gradle_latest)

    libinput
    playerctl
    spotify
    zoom-us
    slack
    signal-desktop
    element-desktop
    nextcloud-client
    cadaver
    libreoffice
    file
    flameshot
    vlc
    evince
    xfce.ristretto
    xfce.exo
    xfce.xfconf
    shotwell
    gimp
    pdftk

    (edid-generator.override {
      modelines = [
        ''Modeline "2560x1440" 241.50 2560 2600 2632 2720 1440 1443 1448 1481 -hsync +vsync''
      ];
    })
    edid-decode
    read-edid

    (pkgs.writeScriptBin "qrpaste" ''
      #! ${pkgs.bash}/bin/bash
      ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.libqrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
    '')

    # experiments
    cachix
  ];

  services.udisks2.enable = true;
  services.devmon.enable = true;
  services.teamviewer.enable = true;
  programs.steam.enable = true;
}
