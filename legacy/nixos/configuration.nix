# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
#
# see https://gist.github.com/dysinger/2a768db5b6e3b729ec898d7d4208add3

{ config, pkgs, lib, ... }:

let
  keepassWithPlugins = pkgs.keepass.override {
    plugins = with pkgs; [
      keepass-keeagent
      keepass-keepassrpc
      keepass-keetraytotp
      keepass-charactercopy
      keepass-qrcodeview
    ];
  };

in {
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./nazarewk.nix
  ];

  # NIX / NIXOS
  nix.autoOptimiseStore = true;
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "21.05";
  location.provider = "geoclue2";

  # BOOT
  boot.kernelParams = [ "consoleblank=90" "nohibernate" ];
  boot.loader.grub.copyKernels = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
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

  # ZFS
  boot.initrd.supportedFilesystems = [ "zfs" ];
  boot.supportedFilesystems = [ "zfs" "ntfs" ];
  boot.zfs.enableUnstable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoSnapshot.enable = true;
  services.zfs.autoSnapshot.flags = "-k -p --utc";
  services.zfs.autoSnapshot.frequent = 12;
  services.zfs.autoSnapshot.daily = 7;
  services.zfs.autoSnapshot.weekly = 6;
  services.zfs.autoSnapshot.monthly = 1;
  services.zfs.trim.enable = true;

  # HARDWARE
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  hardware.cpu.intel.updateMicrocode = true;
  hardware.opengl.driSupport = true;
  hardware.opengl.driSupport32Bit = true;
  boot.initrd.kernelModules = [ "i915" ];
  hardware.opengl.enable = true;
  # https://github.com/NixOS/nixos-hardware/blob/4045d5f43aff4440661d8912fc6e373188d15b5b/common/cpu/intel/default.nix
  hardware.opengl.extraPackages = with pkgs; [
    intel-media-driver # LIBVA_DRIVER_NAME=iHD
    vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
    vaapiVdpau
    libvdpau-va-gl
  ];
  hardware.sane.enable = true;
  hardware.video.hidpi.enable = true;

  # SOUND - PipeWire
  # see additional pavucontrol package
  security.rtkit.enable = true;
  services.pipewire.enable = true;
  services.pipewire.media-session.enable = true;
  services.pipewire.alsa.enable = true;
  services.pipewire.alsa.support32Bit = true;
  services.pipewire.pulse.enable = true;
  services.pipewire.jack.enable = true;
  sound.mediaKeys.enable = true;
  hardware.pulseaudio.extraModules = [
    pkgs.pulseaudio-modules-bt
  ];

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
  systemd.services.ModemManager.enable = true;
  systemd.services.ModemManager.wantedBy = [ "NetworkManager.service" ];

  # LOCALE
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Warsaw";

  # INPUT
  services.xserver.layout = "pl";
  console.useXkbConfig = true;
  services.xserver.libinput.enable = true;
  services.xserver.libinput.touchpad.disableWhileTyping = true;
  services.xserver.libinput.touchpad.naturalScrolling = true;
  services.xserver.libinput.touchpad.tapping = true;
  services.xserver.synaptics.twoFingerScroll = true;

  # YubiKey
  # https://nixos.wiki/wiki/Yubikey
  services.udev.packages = [ pkgs.yubikey-personalization ];

  security.pam.yubico = {
    enable = true;
    # debug = true;
    mode = "challenge-response";
  };

  services.pcscd.enable = true;

  # SSH
  services.openssh.enable = true;
  services.openssh.openFirewall = false;

  # ANDROID
  programs.adb.enable = true;

  # KEYBASE
  services.kbfs.enable = true;
  services.davfs2.enable = true;

  # VM
  virtualisation.docker.autoPrune.enable = true;
  virtualisation.docker.enable = false;
  virtualisation.docker.storageDriver = "zfs";
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

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.interactiveShellInit = ''
    source ${pkgs.grml-zsh-config}/etc/zsh/zshrc
    source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
  '';
  programs.zsh.promptInit = ""; # otherwise it'll override the grml prompt
  programs.zsh.syntaxHighlighting.enable = true;
  programs.zsh.histSize = 100000;

  programs.command-not-found.enable = false;
  programs.bash.interactiveShellInit = ''
    source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
  '';

  programs.seahorse.enable = true;

  # Configure various Sway configs
  # see https://gist.github.com/mschwaig/195fe93ed85dea7aaceaf8e1fc6c0e99
  # see https://nixos.wiki/wiki/Sway#Systemd_integration
  programs.sway.enable = true;
  programs.sway.wrapperFeatures.gtk = true;
  programs.sway.extraPackages = with pkgs; [
    swaylock
    swayidle
    waybar
    wl-clipboard
    wf-recorder
    v4l-utils
    mako
    alacritty
    dmenu
    libappindicator
    libappindicator-gtk3
    grim
    wlogout
    libnotify
    slurp
    qt5.qtwayland

    # audio
    libopenaptx
    libfreeaptx
    pulseaudio

    # sway related
    brightnessctl
    polkit_gnome
    lxappearance
    xsettingsd
    gsettings-desktop-schemas
    gnome.networkmanagerapplet
    gtk_engines
    gtk-engine-murrine
    # wayland programs
    autotiling
    gammastep
    clipman
    wofi
    wev # wayland event viewer
    swayr # window switcher
    kanshi # autorandr
    wshowkeys # display pressed keys
    wdisplays # randr equivalent
  ];
  programs.sway.extraOptions = [ "--debug" ];

  # services.gnome.gnome-keyring.enable replacement goes below:
  services.dbus.packages = [
    pkgs.gnome.gnome-keyring
    pkgs.gcr
  ];
  #security.wrappers.gnome-keyring-daemon = {
  #  source = "${pkgs.gnome.gnome-keyring}/bin/gnome-keyring-daemon";
  #  capabilities = "cap_ipc_lock=ep";
  #};

  programs.sway.extraSessionCommands = ''
    # see https://wiki.debian.org/Wayland#Toolkits
    export GDK_BACKEND=wayland
    export SDL_VIDEODRIVER=wayland
    export QT_QPA_PLATFORM='wayland;xcb'
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    export _JAVA_AWT_WM_NONREPARENTING=1
    export MOZ_ENABLE_WAYLAND=1
    export MOZ_DBUS_REMOTE=1

    eval $(gnome-keyring-daemon --start)
    export SSH_AUTH_SOCK
  '';

  systemd.user.targets.sway-session = {
    description = "Sway compositor session";
    documentation = [ "man:systemd.special(7)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };

  systemd.user.services.sway = {
    description = "Sway - Wayland window manager";
    documentation = [ "man:sway(5)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
    # We explicitly unset PATH here, as we want it to be set by
    # systemctl --user import-environment in startsway
    environment.PATH = lib.mkForce null;
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.dbus}/bin/dbus-run-session /run/current-system/sw/bin/sway
      '';
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

#  systemd.user.services.swayidle = {
#    description = "Idle Manager for Wayland";
#    documentation = [ "man:swayidle(1)" ];
#    wantedBy = [ "sway-session.target" ];
#    partOf = [ "graphical-session.target" ];
#    path = [ pkgs.bash ];
#    serviceConfig = {
#      ExecStart = ''
#        ${pkgs.swayidle}/bin/swayidle -w -d \
#               timeout 300 '${pkgs.sway}/bin/swaymsg "output * dpms off"' \
#               resume '${pkgs.sway}/bin/swaymsg "output * dpms on"'
#             '';
#    };
#  };

  fonts.fonts = with pkgs; [ font-awesome cantarell-fonts noto-fonts ];

  programs.xwayland.enable = true;
  programs.qt5ct.enable = true;
  programs.dconf.enable = true;
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

  xdg.portal.enable = true;
  xdg.portal.gtkUsePortal = true;
  xdg.portal.wlr.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    gnome.gnome-keyring
  ];

  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "qt";

  environment.pathsToLink = [ "/libexec" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    curl
    pstree
    xdg-utils

    zsh-completions
    nix-zsh-completions

    yubioath-desktop
    yubikey-personalization
    yubikey-personalization-gui
    yubikey-manager
    yubikey-manager-qt
    yubico-pam
    gnome.gnome-keyring
    gcr

    pinentry-qt
    pinentry-curses
    pinentry-gnome

    usbutils
    lshw

    # to control pipewire
    pavucontrol

    # themes
    hicolor-icon-theme # see https://github.com/NixOS/nixpkgs/issues/32730
    gnome-icon-theme # see https://github.com/NixOS/nixpkgs/issues/43836#issuecomment-419217138
    gnome3.adwaita-icon-theme
    adwaita-qt
    glib # gsettings
    gnome.dconf-editor

    firefox-wayland
    chromium
    google-chrome
    keepassWithPlugins
    jetbrains.pycharm-professional
    jetbrains.idea-ultimate
    p7zip
    nix-index
    nix-tree
    nix-du
    nixfmt
    nixpkgs-fmt
    system-config-printer

    #fprintd
    #libnfc

    gparted
    tmux

    killall
    bintools
    mc
    htop
    pciutils
    ncdu
    pass
    jq
    lsof
    git
    dig
    cryptsetup
    qrcode
    libqrencode
    imagemagick
    (python39.withPackages (ps:
      with ps; [
        pip
        ipython
        requests
        #python-language-server
        #sanitize-filename
      ]))
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
    gnome.cheese
    libreoffice
    gnome.file-roller
    gnome.gedit
    file
    flameshot
    vlc
    evince
    (xfce.thunar.override {
      thunarPlugins = [ xfce.thunar-archive-plugin xfce.thunar-volman ];
    })
    xfce.ristretto
    xfce.exo
    shotwell

    (edid-generator.override {
      modelines = [
        ''Modeline "2560x1440" 241.50 2560 2600 2632 2720 1440 1443 1448 1481 -hsync +vsync''
      ];
    })
    edid-decode
    read-edid

    (pkgs.writeScriptBin "startsway" ''
      #! ${pkgs.bash}/bin/bash
      systemctl --user import-environment
      exec systemctl --user start sway.service
    '')
    (pkgs.writeScriptBin "_sway-init" ''
            #! ${pkgs.bash}/bin/bash
            set -x
            while ! systemctl --user show-environment | grep WAYLAND_DISPLAY && sleep 1; do
      	      systemctl --user import-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
            done
            dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP
            /run/current-system/sw/libexec/polkit-gnome-authentication-agent-1
            systemctl --user start sway-session.target
            touch /tmp/sway-started
          '')
    (pkgs.writeScriptBin "_sway-wait" ''
      #! ${pkgs.bash}/bin/bash
      set -x
      interval=3
      until [ -f /tmp/sway-started ] ; do sleep "$interval"; done
      echo 'WAYLAND_DISPLAY available'
      until pgrep -u $UID waybar ; do sleep "$interval"; done
      echo 'Waybar started'
    '')

    (pkgs.writeScriptBin "qrpaste" ''
      #! ${pkgs.bash}/bin/bash
      ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.libqrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
    '')

    # experiments
    cachix
  ];

  services.gvfs.enable = true; # Mount, trash, and other functionalities
  services.tumbler.enable = true; # Thumbnail support for images
  services.teamviewer.enable = true;
  programs.steam.enable = true;
}
