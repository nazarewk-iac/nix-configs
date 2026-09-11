# The command-line tool groups, as den aspects. It ports the whole `toolset` area of the old tree.
#
# Old path:
# modules/universal/toolset/
#
# The old tree keeps every byte. This file is the parallel den implementation.
#
# ## Eleven aspects in one file
#
# The old area holds 12 modules, and each one carries its own `enable`. A den aspect has no
# `enable`: inclusion is the switch. So each group becomes one aspect, and a consumer includes the
# groups it wants. One file holds all eleven, because the batch owns one file per old area. den
# reads the file once, no matter how many registry names point at it. Measured 2026-09-11.
#
# Two old modules get no aspect here. `toolset/ide` and `toolset/print-3d` hold a forward-write
# only, into `kdn.programs.*` and `kdn.development.*`. Those two areas reach den in batch 8 and in
# batch 9, so an aspect for them would resolve to an empty module list today. They land with those
# batches.
#
# ## What the port changes
#
# 1. **`kdn.env.packages` does not survive.** Design B: a target names its class, so it writes the
#    native option. A `nixos` or a `darwin` target writes `environment.systemPackages`. A
#    `homeManager` target writes `home.packages`. The `apply` filter of the old option moves to
#    ../common/filter-packages.nix, and each list opts in through `filterPackagesFor`.
# 2. **A guard becomes a class.** `ifNotHMParent` becomes the `homeManager` class. An unguarded
#    write becomes all three classes. `ifTypes [ "nixos" ]` becomes the `nixos` class. The
#    `ifHMParent` forward disappears: den partitions by scope, so a host includes a user aspect at
#    user scope.
# 3. **A forward-write of a sibling group becomes an `includes` edge.** `toolset/fs` writes
#    `tracing` and `fs/encryption`; `toolset/unix` writes `tracing`. Each write was a `mkDefault`
#    inside a NixOS guard, and each included aspect emits nothing outside the `nixos` class or
#    outside Linux. So an unconditional `includes` keeps the same result on every platform.
# 4. **`pkgs.kdn.*` becomes a relative `callPackage`.** An aspect must work with no overlay of this
#    repository, so `pkgs.kdn.whicher`, `pkgs.kdn.kdn-nix` and `pkgs.kdn.systemd-cryptsetup` become
#    `pkgs.callPackage ../../../packages/<name> { }`. This follows the `zellij` aspect.
# 5. **A desktop-only list becomes its own aspect.** The old `network` module reads
#    `config.kdn.desktop.enable` to add the Wireshark GUI. den has no desktop aspect yet, and
#    inclusion is the switch, so `toolset-network-gui` holds that one package and includes
#    `toolset-network`.
#
# ## Four forward-writes wait for a later batch
#
# Each one names an area with no den aspect today. The line is an `includes` edge, and it lands
# when the target aspect lands:
#
# | this aspect | the option it wrote | the batch that unblocks it |
# |---|---|---|
# | `toolset-essentials` | `kdn.programs.handlr.enable` | batch 8 |
# | `toolset-fs` | `kdn.programs.midnight-commander.enable` | batch 8 |
# | `toolset-network` | `kdn.services.iperf3.enable` | batch 10 |
# | `toolset-nix` | nothing; it is complete | — |
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch. No aspect below declares one.
# 3. **No custom module argument.** Every target module below takes `lib` and `pkgs` only.
{ kdn, ... }:
let
  # The `apply` pipeline of the old package option, as a plain function. It drops a broken,
  # unsupported, unavailable or non-evaluating package, and it warns once per group. A list that
  # holds a Linux-only package therefore stays safe on a darwin consumer.
  filterPackagesFor = lib: import ../common/filter-packages.nix { inherit lib; };

  # Two writers, one per native option. Each one takes a `lib: pkgs:` package-list function.
  mkSystem =
    packages:
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filterPackagesFor lib (packages lib pkgs);
    };

  mkHome =
    packages:
    { lib, pkgs, ... }:
    {
      home.packages = filterPackagesFor lib (packages lib pkgs);
    };

  # ------------------------------------------------------------------ diagrams

  diagramsPackages =
    lib: pkgs: with pkgs; [
      mermaid-cli
      drawio
      plantuml
    ];

  # ------------------------------------------------------------------ essentials

  essentialsPackages =
    lib: pkgs: with pkgs; [
      curl
      openssh
      screen
      tmux
      wget

      # Working with XDG files
      file
      desktop-file-utils
      xdg-utils

      # https://wiki.archlinux.org/title/Default%20applications#Resource_openers
      mimeo

      jq
      git
      openssl

      findutils
      # A higher priority than the `kill` of util-linux.
      (lib.hiPrio coreutils)
      moreutils
      gnugrep
      ripgrep

      zip
      unzip

      (pkgs.callPackage ../../../packages/whicher { })

      # serial console use
      minicom
    ];

  # ------------------------------------------------------------------ fs

  fsPackages =
    lib: pkgs: with pkgs; [
      bintools
      file
      ncdu
      tree

      # Run a command on a change. https://eradman.com/entrproject/
      entr
      # A cross-platform stand-in for inotify-tools.
      fswatch
      watchexec
    ];

  fsNixosPackages =
    lib: pkgs: with pkgs; [
      inotify-info
      inotify-tools

      dosfstools
      # The userspace tool for the exfat kernel module of Linux 5.7 and later.
      exfatprogs
      gptfdisk
      ntfs3g
    ];

  # ------------------------------------------------------------------ fs encryption

  # `clevis` and `jose` do not build on macOS, so the list drops them there.
  encryptionPackages =
    lib: pkgs:
    lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin) (
      with pkgs;
      [
        clevis
        jose
      ]
    );

  encryptionNixosPackages =
    lib: pkgs:
    let
      systemd-cryptsetup = pkgs.callPackage ../../../packages/systemd-cryptsetup { };
    in
    (with pkgs; [
      cryptsetup
      sbctl
      tpm2-tools
      tpm2-tss
    ])
    ++ [
      systemd-cryptsetup
      (pkgs.writeShellApplication {
        name = "kdn-systemd-zfs-decrypt";
        runtimeInputs = [ systemd-cryptsetup ];
        text = ''
          set -eEuo pipefail
          set -x

          usage() {
            cat <<'EOF' >&2
          kdn-systemd-zfs-decrypt XXX-main-crypted /dev/disk/by-id/encrypted-zpool /dev/disk/by-id/header-partition
          EOF
            exit 1
          }

          main() {
            name="$1"
            disk="$2"
            header="$3"

            systemd-cryptsetup attach "$name" "$disk" - header="$header"
          }

          main "$@" || usage
        '';
      })
    ];

  # ------------------------------------------------------------------ logs processing

  logsPackages =
    lib: pkgs: with pkgs; [
      # https://github.com/rcoh/angle-grinder
      angle-grinder
    ];

  # ------------------------------------------------------------------ mikrotik

  mikrotikPackages = lib: pkgs: [ (lib.lowPrio pkgs.winbox) ];

  # ------------------------------------------------------------------ network

  networkPackages =
    lib: pkgs: with pkgs; [
      (lib.meta.setPrio 10 nettools)
      # telnet and friends
      (lib.meta.setPrio 20 inetutils)
      socat
      arp-scan
      # It gives dnssec-* and named-*.
      bind
      # Another output of bind. It gives dig, delv, nslookup and nsupdate.
      dnsutils
      nmap
      bandwhich
      tcpdump
      iperf
      speedtest-go
      speedtest-cli
      ssh-tools
      (lib.hiPrio wireshark-cli)
    ];

  networkNixosPackages =
    lib: pkgs: with pkgs; [
      conntrack-tools
      ebtables
      ethtool
      iptables
      nftables
    ];

  # The Qt user interface of Wireshark. It is the whole content of `toolset-network-gui`.
  networkGuiPackages = lib: pkgs: [ (lib.lowPrio pkgs.wireshark) ];

  # ------------------------------------------------------------------ nix

  nixPackages =
    lib: pkgs:
    (with pkgs; [
      # pretty-derivation
      nix-derivation
      # It reports which packages a cache holds.
      nix-weather
      nix-output-monitor
      nix-du
      nix-tree
      nix-update
    ])
    ++ [ (pkgs.callPackage ../../../packages/kdn-nix { }) ];

  # ------------------------------------------------------------------ unix

  unixPackages =
    lib: pkgs: with pkgs; [
      btop
      htop
      pstree
      (lib.meta.setPrio 10 util-linux)
      pv
    ];

  unixNixosPackages =
    lib: pkgs:
    (with pkgs; [
      sysstat
      iotop

      # A stand-in for strace.
      lurk
      pstree
      strace
      # It moved out of kernelPackages.
      perf
    ])
    ++ [
      (pkgs.writeShellApplication {
        name = "get-proc-env";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          jq -R 'split("\u0000") | map(split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries' "/proc/$1/environ"
        '';
      })
    ]
    ++ (lib.pipe pkgs.unixtools [
      (
        s:
        builtins.removeAttrs s [
          "procps"
          "util-linux"
          "nettools"
          "recurseForDerivations"
        ]
      )
      builtins.attrValues
    ]);
in
{
  # ------------------------------------------------------------------ toolset-diagrams

  kdn.toolset-diagrams.homeManager = mkHome diagramsPackages;

  # ------------------------------------------------------------------ toolset-essentials

  kdn.toolset-essentials.nixos = mkSystem essentialsPackages;
  kdn.toolset-essentials.darwin = mkSystem essentialsPackages;
  kdn.toolset-essentials.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filterPackagesFor lib (essentialsPackages lib pkgs);

      # A `lib.mkDefault` on each, so a consumer drops difftastic or picks a light background.
      programs.difftastic.enable = lib.mkDefault true;
      programs.difftastic.options.background = lib.mkDefault "dark";
    };

  # ------------------------------------------------------------------ toolset-fs

  kdn.toolset-fs.includes = [
    kdn.toolset-tracing
    kdn.toolset-fs-encryption
  ];

  kdn.toolset-fs.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filterPackagesFor lib (
        (fsPackages lib pkgs) ++ (fsNixosPackages lib pkgs)
      );
    };

  kdn.toolset-fs.darwin = mkSystem fsPackages;

  kdn.toolset-fs.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filterPackagesFor lib (fsPackages lib pkgs);

      programs.yazi.enable = true;
      programs.yazi.enableBashIntegration = true;
      programs.yazi.enableFishIntegration = true;
      programs.yazi.enableZshIntegration = true;
      programs.yazi.shellWrapperName = "y";

      programs.superfile.enable = true;
      programs.superfile.settings.theme = "dracula";

      programs.zoxide.enable = true;
      programs.zoxide.enableBashIntegration = true;
      programs.zoxide.enableFishIntegration = true;
      programs.zoxide.enableZshIntegration = true;
    };

  # ------------------------------------------------------------------ toolset-fs-encryption

  kdn.toolset-fs-encryption.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filterPackagesFor lib (
        (encryptionPackages lib pkgs) ++ (encryptionNixosPackages lib pkgs)
      );
    };

  kdn.toolset-fs-encryption.darwin = mkSystem encryptionPackages;
  kdn.toolset-fs-encryption.homeManager = mkHome encryptionPackages;

  # ------------------------------------------------------------------ toolset-logs-processing

  kdn.toolset-logs-processing.includes = [ kdn.apps ];

  kdn.toolset-logs-processing.nixos = mkSystem logsPackages;
  kdn.toolset-logs-processing.darwin = mkSystem logsPackages;

  kdn.toolset-logs-processing.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filterPackagesFor lib (logsPackages lib pkgs);

      kdn.apps.lnav.enable = true;
      kdn.apps.lnav.package.original = pkgs.lnav;
      kdn.apps.lnav.dirs.config = [ "lnav" ];
    };

  # ------------------------------------------------------------------ toolset-mikrotik

  kdn.toolset-mikrotik.includes = [
    kdn.apps
    kdn.emulation-wine
  ];

  kdn.toolset-mikrotik.nixos = mkSystem mikrotikPackages;
  kdn.toolset-mikrotik.darwin = mkSystem mikrotikPackages;

  kdn.toolset-mikrotik.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filterPackagesFor lib (mikrotikPackages lib pkgs);

      kdn.apps.winbox4.enable = true;
      kdn.apps.winbox4.dirs.data = [ "MikroTik/WinBox" ];
    };

  # ------------------------------------------------------------------ toolset-network

  kdn.toolset-network.nixos =
    { lib, pkgs, ... }:
    {
      programs.wireshark.enable = true;
      environment.systemPackages = filterPackagesFor lib (
        (networkPackages lib pkgs) ++ (networkNixosPackages lib pkgs)
      );
    };

  kdn.toolset-network.darwin = mkSystem networkPackages;
  kdn.toolset-network.homeManager = mkHome networkPackages;

  # ------------------------------------------------------------------ toolset-network-gui

  kdn.toolset-network-gui.includes = [ kdn.toolset-network ];

  kdn.toolset-network-gui.nixos = mkSystem networkGuiPackages;
  kdn.toolset-network-gui.darwin = mkSystem networkGuiPackages;
  kdn.toolset-network-gui.homeManager = mkHome networkGuiPackages;

  # ------------------------------------------------------------------ toolset-nix

  kdn.toolset-nix.homeManager = mkHome nixPackages;

  kdn.toolset-nix.nixos = {
    programs.fish.interactiveShellInit = ''
      complete -c kdn-nix-which --wraps which
    '';
  };

  # ------------------------------------------------------------------ toolset-tracing

  kdn.toolset-tracing.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filterPackagesFor lib [ pkgs.bpftrace ];

      # It gives opensnoop.
      programs.bcc.enable = true;
    };

  # ------------------------------------------------------------------ toolset-unix

  kdn.toolset-unix.includes = [ kdn.toolset-tracing ];

  kdn.toolset-unix.nixos =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filterPackagesFor lib (
        (unixPackages lib pkgs) ++ (unixNixosPackages lib pkgs)
      );
    };

  kdn.toolset-unix.darwin = mkSystem unixPackages;
  kdn.toolset-unix.homeManager = mkHome unixPackages;
}
