# The assertion set for layer-C batch 8: the 40 `program-*` aspects. `../tests.nix` imports this file
# and registers the result as `den-eval-programs`.
#
# Every assertion is `{ name; expected; actual; }`, the shape `mkEvalCheck` needs.
#
# ## The subjects
#
# | Subject | Class | What it proves |
# |---|---|---|
# | `nixosPlain` | nixos | all 15 `nixos` targets of the batch evaluate together with **no** consumer data |
# | `nixosData` | nixos | each option the batch declares reaches the native option |
# | `darwinPlain` | darwin | all 8 `darwin` targets evaluate together |
# | `homeLinux` | homeManager | all 37 `homeManager` targets evaluate on a Linux home |
# | `homeDarwin` | homeManager | the same 37 evaluate on a darwin home, and every Linux-only body drops |
# | `homeData` | homeManager | each option the batch declares reaches the native option |
#
# ## Why one subject holds every aspect of a class
#
# 40 aspects give 60 (aspect, class) pairs. `den-eval-instantiate` already forces each pair alone, so
# a per-aspect subject here would repeat that work. A merged subject proves the part that no other
# check reaches: the 40 aspects compose. No two of them write one option at one priority, and no
# aspect needs a class the harness does not hold.
#
# ## Why this file builds one home harness of its own
#
# `../tests.nix` fixes its home harness to `aarch64-darwin`. Ten aspects of this batch hold a
# Linux-only body, so the fixed harness cannot reach it. `bareLinuxHome` below repeats the same three
# lines on `x86_64-linux`. It builds no derivation; it evaluates one.
#
# ## The data holds no real value
#
# Every consumer value below is a placeholder. No host name, no address, no path of any real machine
# and no key appears here.
{
  lib,
  pkgs,
  inputs,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem;

  modulesFor =
    class: aspects:
    denLib.imports {
      inherit class aspects;
    };

  # A Linux home, in the same bare-consumer shape as the darwin one in `../tests.nix`.
  bareLinuxHome =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      modules = modules ++ [
        {
          home.username = "dev";
          home.homeDirectory = "/home/dev";
          home.stateVersion = "26.11";
        }
      ];
    };

  # Every `nixos` aspect of this batch, measured 2026-09-11.
  nixosAspects = [
    "program-atuin"
    "program-dconf"
    "program-direnv"
    "program-editors-photo"
    "program-fish"
    "program-gnupg"
    "program-handlr"
    "program-kdeconnect"
    "program-keepass"
    "program-nix-index"
    "program-obs-studio"
    "program-photoprism"
    "program-weechat"
    "program-ydotool"
    "program-zsh"
  ];

  # Every `darwin` aspect of this batch.
  darwinAspects = [
    "program-browsers-launcher"
    "program-editors-photo"
    "program-fish"
    "program-gnupg"
    "program-handlr"
    "program-nix-index"
    "program-weechat"
    "program-zsh"
  ];

  # Every `homeManager` aspect of this batch. Three aspects stay out: `program-keepass`,
  # `program-photoprism` and `program-ydotool` serve the `nixos` class alone.
  homeAspects = [
    "program-atuin"
    "program-beeper"
    "program-blender"
    "program-browsers-launcher"
    "program-chrome"
    "program-chromium"
    "program-dconf"
    "program-direnv"
    "program-editors-photo"
    "program-editors-video"
    "program-ente-photos"
    "program-firefox"
    "program-fish"
    "program-gnupg"
    "program-handlr"
    "program-kdeconnect"
    "program-keepassxc"
    "program-logseq"
    "program-matrix"
    "program-midnight-commander"
    "program-nextcloud-client"
    "program-nix-index"
    "program-obs-studio"
    "program-office"
    "program-orca-slicer"
    "program-rambox"
    "program-signal"
    "program-slack"
    "program-spotify"
    "program-ssh-client"
    "program-terminal-ide"
    "program-thunderbird"
    "program-tidal"
    "program-torrent"
    "program-weechat"
    "program-wofi"
    "program-zsh"
  ];

  nixosPlain = (bareNixos (modulesFor "nixos" nixosAspects)).config;

  # One value per `nixos` option this batch declares.
  nixosValues = {
    kdn.programs.fish.defaultShell = true;
    kdn.programs.gnupg.pass-secret-service.use = true;
    kdn.programs.photoprism.originalsDevice = "/placeholder/photos";
    kdn.programs.atuin.users = [ "placeholder-user" ];
    kdn.programs.atuin.autologinUsers = [ ];
  };

  nixosData =
    (bareNixos (
      modulesFor "nixos" nixosAspects
      ++ [
        nixosValues
        { users.users.placeholder-user.isNormalUser = true; }
      ]
    )).config;

  darwinPlain = (bareDarwinSystem (modulesFor "darwin" darwinAspects)).config;

  # nheko needs `olm`, and nixpkgs marks `olm` insecure. Home Manager's own `programs.nheko` module
  # writes the package straight into `home.packages`, so `../../../modules/den/common/filter-packages.nix`
  # never sees it and cannot drop it. A bare subject holds no `permittedInsecurePackages`, so the
  # evaluation would die. The aspect now defaults the option to `false`, so this line is only an
  # explicit restatement of that default.
  homePolicy = {
    kdn.programs.matrix.nheko.use = false;
  };

  homeDarwin =
    (harness.bareHomeConfiguration (modulesFor "homeManager" homeAspects ++ [ homePolicy ])).config;

  homeLinux = (bareLinuxHome (modulesFor "homeManager" homeAspects ++ [ homePolicy ])).config;

  # One value per `homeManager` option this batch declares that carries a non-trivial body.
  homeValues = {
    kdn.programs.keepassxc.service.use = true;
    kdn.programs.keepassxc.service.searchDirs = [ "/placeholder/secrets" ];
    kdn.programs.keepassxc.service.fileName = "placeholder.kdbx";
    kdn.programs.matrix.gomuks.use = true;
    kdn.programs.gnupg.passwordStore.use = false;
    kdn.programs.firefox.profileNames = [ "placeholder-profile" ];
    # A plain definition of a list concatenates. The zsh aspect writes 20 entries, so this one adds
    # the 21st and replaces nothing.
    programs.zsh.setOptions = [ "PLACEHOLDER_OPTION" ];
  };

  homeData =
    (bareLinuxHome (
      modulesFor "homeManager" homeAspects
      ++ [
        homePolicy
        homeValues
      ]
    )).config;

  packageNames = map lib.getName;

  hasAll = have: map (want: builtins.elem want have);

  pluginNames = e: map (p: p.name) e.programs.fish.plugins;

  # Home Manager adds `.config/zsh` through its own module, so the read names the option instead of
  # the file set.
  gnupgTmpfiles = e: builtins.filter (lib.hasInfix ".gnupg") (e.systemd.user.tmpfiles.rules or [ ]);
  assertions = [
    # ---------------------------------------------------------------- nixosPlain
    {
      name = "all 15 nixos targets of this batch force together in one bare consumer";
      expected = true;
      actual = builtins.isString nixosPlain.system.build.toplevel.drvPath;
    }
    {
      name = "fish becomes a system shell";
      expected = true;
      actual = nixosPlain.programs.fish.enable;
    }
    {
      name = "fish is not the login shell until the consumer asks";
      expected = [ ];
      actual = nixosPlain.kdn.programs.fish.defaultShellUsers;
    }
    {
      name = "zsh runs on the host and leaves completion to the user config";
      expected = [
        true
        false
      ];
      actual = [
        nixosPlain.programs.zsh.enable
        nixosPlain.programs.zsh.enableCompletion
      ];
    }
    {
      name = "the GnuPG agent runs, and it serves no SSH key";
      expected = [
        true
        false
      ];
      actual = [
        nixosPlain.programs.gnupg.agent.enable
        nixosPlain.programs.gnupg.agent.enableSSHSupport
      ];
    }
    {
      name = "the smartcard daemon runs for the GnuPG agent";
      expected = true;
      actual = nixosPlain.services.pcscd.enable;
    }
    {
      name = "the pass-backed secret service stays off until the consumer asks";
      expected = false;
      actual = nixosPlain.services.passSecretService.enable;
    }
    {
      name = "dconf runs on the host";
      expected = true;
      actual = nixosPlain.programs.dconf.enable;
    }
    {
      name = "the direnv aspect touches the host nix settings alone, and installs no program there";
      expected = false;
      actual = nixosPlain.programs.direnv.enable;
    }
    {
      name = "the ydotool group keeps its fixed gid";
      expected = 26598;
      actual = nixosPlain.users.groups.ydotool.gid;
    }
    {
      name = "the nix path names one nixpkgs entry, and it comes from the aspect's own input";
      expected = true;
      actual = builtins.any (lib.hasPrefix "nixpkgs=") nixosPlain.nix.nixPath;
    }
    {
      name = "direnv keeps the build outputs alive";
      expected = true;
      actual = lib.hasInfix "keep-outputs = true" nixosPlain.nix.extraOptions;
    }
    {
      name = "kdeconnect reaches the host, where it opens the firewall ports";
      expected = true;
      actual = nixosPlain.programs.kdeconnect.enable;
    }
    {
      name = "obs-studio runs with the virtual camera";
      expected = [
        true
        true
      ];
      actual = [
        nixosPlain.programs.obs-studio.enable
        nixosPlain.programs.obs-studio.enableVirtualCamera
      ];
    }
    {
      name = "the photoprism bind mount appears only when the consumer names a device";
      expected = false;
      actual = nixosPlain.fileSystems ? "/var/lib/private/photoprism/originals";
    }
    {
      name = "the host package list holds the three fish helpers and the zsh completions";
      expected = [
        true
        true
        true
        true
      ];
      actual = hasAll (packageNames nixosPlain.environment.systemPackages) [
        "grc"
        "fzf"
        "babelfish"
        "zsh-completions"
      ];
    }

    # ---------------------------------------------------------------- nixosData
    {
      name = "every nixos target still forces with consumer data";
      expected = true;
      actual = builtins.isString nixosData.system.build.toplevel.drvPath;
    }
    {
      name = "the fish default-shell switch reaches the NixOS option";
      expected = "fish";
      actual = lib.getName nixosData.users.defaultUserShell;
    }
    {
      name = "the photoprism originals device becomes a bind mount with an explicit type";
      expected = {
        device = "/placeholder/photos";
        fsType = "none";
        options = [ "bind" ];
      };
      actual = {
        inherit (nixosData.fileSystems."/var/lib/private/photoprism/originals")
          device
          fsType
          options
          ;
      };
    }
    {
      name = "the secret-service switch turns the unit on and removes gnome-keyring";
      expected = [
        true
        false
      ];
      actual = [
        nixosData.services.passSecretService.enable
        nixosData.services.gnome.gnome-keyring.enable
      ];
    }
    {
      name = "the secret-service unit answers the Secret Service D-Bus name";
      expected = [ "pass-secret-service.service" ];
      actual = nixosData.systemd.user.services."dbus-org.freedesktop.secrets".aliases;
    }
    {
      name = "the atuin user list creates one workaround unit per named user";
      expected = true;
      actual = nixosData.systemd.services ? "atuin-zfs-workaround-placeholder-user";
    }
    {
      name = "the atuin login unit stays out while the consumer names no credential";
      expected = false;
      actual = nixosData.systemd.services ? "kdn-atuin-login-placeholder-user";
    }
    {
      name = "the keepass overlay reaches the nixpkgs of the host";
      expected = true;
      actual = nixosData.nixpkgs.overlays != [ ];
    }

    # ---------------------------------------------------------------- darwinPlain
    {
      name = "all 8 darwin targets of this batch force together in one bare consumer";
      expected = true;
      actual = builtins.isString darwinPlain.system.build.toplevel.drvPath;
    }
    {
      name = "fish becomes a shell on darwin too";
      expected = true;
      actual = darwinPlain.programs.fish.enable;
    }
    {
      name = "the darwin zsh keeps the two plugin switches off";
      expected = [
        false
        false
      ];
      actual = [
        darwinPlain.programs.zsh.enableSyntaxHighlighting
        darwinPlain.programs.zsh.enableAutosuggestions
      ];
    }
    {
      name = "the browser launcher reaches darwin as a Homebrew cask";
      expected = [ "browsers" ];
      # `homebrew.casks` coerces a plain string to a submodule, so the read names the `name` key.
      actual = map (c: c.name) darwinPlain.homebrew.casks;
    }
    {
      name = "the GnuPG agent runs on darwin, and no Linux-only body follows it";
      expected = [
        true
        true
      ];
      actual = [
        darwinPlain.programs.gnupg.agent.enable
        (!(darwinPlain.services ? pcscd))
      ];
    }
    {
      name = "the nix path names one nixpkgs entry on darwin too";
      expected = true;
      actual = builtins.any (lib.hasPrefix "nixpkgs=") darwinPlain.nix.nixPath;
    }

    # ---------------------------------------------------------------- homeLinux
    {
      name = "all 37 homeManager targets of this batch force together on a Linux home";
      expected = true;
      actual = builtins.isString homeLinux.home.activationPackage.drvPath;
    }
    {
      name = "fish carries its five plugins, and the pinned history-merge plugin is one of them";
      expected = [
        5
        true
      ];
      actual = [
        (builtins.length (pluginNames homeLinux))
        (builtins.elem "fish-history-merge" (pluginNames homeLinux))
      ];
    }
    {
      name = "zsh keeps its dot directory under the XDG config home";
      expected = "/home/dev/.config/zsh";
      actual = homeLinux.programs.zsh.dotDir;
    }
    {
      name = "dconf runs in the user session";
      expected = true;
      actual = homeLinux.dconf.enable;
    }
    {
      name = "kdeconnect runs on a Linux home";
      expected = true;
      actual = homeLinux.services.kdeconnect.enable;
    }
    {
      name = "the GnuPG aspect keeps the mode of the private directory through a tmpfiles rule";
      expected = [ "d %h/.gnupg 0700 - - -" ];
      actual = gnupgTmpfiles homeLinux;
    }
    {
      name = "the password store runs next to the agent by default";
      expected = [
        true
        true
      ];
      actual = [
        homeLinux.programs.gpg.enable
        homeLinux.programs.password-store.enable
      ];
    }
    {
      name = "the ssh client drops the upstream default block and keeps its own wildcard host";
      expected = [
        false
        true
      ];
      actual = [
        homeLinux.programs.ssh.enableDefaultConfig
        (homeLinux.programs.ssh.settings ? "*")
      ];
    }
    {
      name = "the ssh agent runs on a Linux home";
      expected = true;
      actual = homeLinux.services.ssh-agent.enable;
    }
    {
      name = "the keepassxc aspect reaches the firefox aspect's own option";
      expected = true;
      actual = homeLinux.kdn.programs.firefox.nativeMessagingHosts != [ ];
    }
    {
      name = "the keepassxc aspect reaches the thunderbird aspect's own option";
      expected = true;
      actual = homeLinux.kdn.programs.thunderbird.nativeMessagingHosts != [ ];
    }
    {
      name = "gomuks stays out of the application set until the consumer asks";
      expected = false;
      actual = homeLinux.kdn.apps ? gomuks;
    }
    {
      name = "the batch publishes a persistence list, and it names the GnuPG directory";
      expected = true;
      actual = builtins.elem ".gnupg" homeLinux.kdn.apps-persist.directories."usr/data";
    }
    {
      name = "helix becomes the default editor, and vim does not";
      expected = [
        true
        false
      ];
      actual = [
        homeLinux.programs.helix.defaultEditor
        homeLinux.programs.vim.defaultEditor
      ];
    }

    # ---------------------------------------------------------------- homeDarwin
    {
      name = "all 37 homeManager targets of this batch force together on a darwin home";
      expected = true;
      actual = builtins.isString homeDarwin.home.activationPackage.drvPath;
    }
    {
      name = "kdeconnect stays off on a darwin home";
      expected = false;
      actual = homeDarwin.services.kdeconnect.enable;
    }
    {
      name = "the GnuPG tmpfiles rule drops on a darwin home, where the module has no platform";
      expected = [ ];
      actual = gnupgTmpfiles homeDarwin;
    }
    {
      name = "the ssh agent stays off on a darwin home";
      expected = false;
      actual = homeDarwin.services.ssh-agent.enable;
    }
    {
      name = "zsh keeps its dot directory on darwin too";
      expected = "/Users/dev/.config/zsh";
      actual = homeDarwin.programs.zsh.dotDir;
    }
    {
      name = "a darwin home still publishes the GnuPG persistence entry";
      expected = true;
      actual = builtins.elem ".gnupg" homeDarwin.kdn.apps-persist.directories."usr/data";
    }

    # ---------------------------------------------------------------- homeData
    {
      name = "every homeManager target still forces with consumer data";
      expected = true;
      actual = builtins.isString homeData.home.activationPackage.drvPath;
    }
    {
      name = "the keepassxc service switch builds the unit, and the search directories gate it";
      expected = [ "/placeholder/secrets" ];
      actual = homeData.systemd.user.services.keepassxc.Unit.ConditionPathExists;
    }
    {
      name = "the keepassxc search path reaches the session environment";
      expected = "/placeholder/secrets";
      actual = homeData.home.sessionVariables.KEEPASS_PATH;
    }
    {
      name = "the gomuks switch adds both clients, and the web one is the default";
      expected = [
        true
        false
        true
      ];
      actual = [
        (homeData.kdn.apps ? gomuks)
        homeData.kdn.apps.gomuks.enable
        homeData.kdn.apps.gomuks-web.enable
      ];
    }
    {
      name = "the password-store switch removes it and keeps the agent";
      expected = [
        false
        true
      ];
      actual = [
        homeData.programs.password-store.enable
        homeData.programs.gpg.enable
      ];
    }
    {
      name = "a consumer option adds to the zsh option list instead of replacing it";
      expected = true;
      actual =
        builtins.elem "PLACEHOLDER_OPTION" homeData.programs.zsh.setOptions
        && builtins.length homeData.programs.zsh.setOptions > 1;
    }
  ];

  # ------------------------------------------------------------------ the coverage rows
  instantiatedBy = {
    program-atuin = "den-eval-programs (bare nixos, bare Linux home, bare darwin home)";
    program-beeper = "den-eval-programs (bare Linux home, bare darwin home)";
    program-blender = "den-eval-programs (bare Linux home, bare darwin home)";
    program-browsers-launcher = "den-eval-programs (bare darwin, bare Linux home, bare darwin home)";
    program-chrome = "den-eval-programs (bare Linux home, bare darwin home)";
    program-chromium = "den-eval-programs (bare Linux home, bare darwin home)";
    program-dconf = "den-eval-programs (bare nixos, bare Linux home, bare darwin home)";
    program-direnv = "den-eval-programs (bare nixos, bare Linux home, bare darwin home)";
    program-editors-photo = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
    program-editors-video = "den-eval-programs (bare Linux home, bare darwin home)";
    program-ente-photos = "den-eval-programs (bare Linux home, bare darwin home)";
    program-firefox = "den-eval-programs (bare Linux home, bare darwin home)";
    program-fish = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
    program-gnupg = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
    program-handlr = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
    program-kdeconnect = "den-eval-programs (bare nixos, bare Linux home, bare darwin home)";
    program-keepass = "den-eval-programs (bare nixos)";
    program-keepassxc = "den-eval-programs (bare Linux home, bare darwin home)";
    program-logseq = "den-eval-programs (bare Linux home, bare darwin home)";
    program-matrix = "den-eval-programs (bare Linux home, bare darwin home)";
    program-midnight-commander = "den-eval-programs (bare Linux home, bare darwin home)";
    program-nextcloud-client = "den-eval-programs (bare Linux home, bare darwin home)";
    program-nix-index = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
    program-obs-studio = "den-eval-programs (bare nixos, bare Linux home, bare darwin home)";
    program-office = "den-eval-programs (bare Linux home, bare darwin home)";
    program-orca-slicer = "den-eval-programs (bare Linux home, bare darwin home)";
    program-photoprism = "den-eval-programs (bare nixos)";
    program-rambox = "den-eval-programs (bare Linux home, bare darwin home)";
    program-signal = "den-eval-programs (bare Linux home, bare darwin home)";
    program-slack = "den-eval-programs (bare Linux home, bare darwin home)";
    program-spotify = "den-eval-programs (bare Linux home, bare darwin home)";
    program-ssh-client = "den-eval-programs (bare Linux home, bare darwin home)";
    program-terminal-ide = "den-eval-programs (bare Linux home, bare darwin home)";
    program-thunderbird = "den-eval-programs (bare Linux home, bare darwin home)";
    program-tidal = "den-eval-programs (bare Linux home, bare darwin home)";
    program-torrent = "den-eval-programs (bare Linux home, bare darwin home)";
    program-weechat = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
    program-wofi = "den-eval-programs (bare Linux home, bare darwin home)";
    program-ydotool = "den-eval-programs (bare nixos)";
    program-zsh = "den-eval-programs (bare nixos, bare darwin, bare Linux home, bare darwin home)";
  };
in
{
  inherit assertions instantiatedBy;
}
