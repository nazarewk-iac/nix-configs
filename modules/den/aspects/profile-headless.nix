# The `headless/base` module of the old tree, as four den aspects.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# `profile-headless` is a bundle. It names the aspects a headless machine needs, and it carries the
# sudo, sysctl, polkit and XDG-persist opinions of the old module. Three leaves carry one tool each.
#
# ## Class list
#
#   - `profile-headless` — `nixos`, `darwin` and `homeManager`
#   - `profile-headless-zellij`, `profile-headless-vim`, `profile-headless-wezterm` — `homeManager`
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The 13 `enable` writes become `includes` entries.** den collapses a diamond, so several
#    aspects may name the same one.
# 3. **The three sub-switches become three aspects.** The old module declares `zellij.enable`,
#    `vim.enable` and `wezterm.enable`. Each one is a reachable `enable`, and rule 2 forbids that. A
#    leaf aspect is the den switch: a consumer drops one leaf and keeps the other two.
# 4. **`kdn.programs.fish.defaultShell` goes.** An aspect writes no option of another aspect. The
#    consumer wires that value on `program-fish`.
# 5. **`kdn.toolset.ide.enable` becomes `program-terminal-ide`.** The registry holds no
#    `toolset-ide` name. `modules/universal/toolset/ide/default.nix` is a pure forwarder: it writes
#    `kdn.programs.terminal-ide.enable`, plus `kdn.development.jetbrains.enable` only when a desktop
#    is present. A headless machine has no desktop, so this bundle names the terminal IDE alone.
# 6. **The dead stylix theme write goes.** `headless/base/default.nix:132-135` writes
#    `programs.zellij.themes.stylix.default` with a body that is fully commented out, so the value
#    is an empty attribute set. The `with` never forces a stylix colour. The line adds nothing, and
#    it would make every consumer supply stylix.
# 7. **`kdn.env.packages` goes.** Each target writes the native package option of its own class.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** See change 3.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  # The old module keeps these three variables across a `sudo` call, so a nested shell still knows
  # it runs inside zellij.
  sudoConfig = ''
    Defaults  env_keep += ZELLIJ
    Defaults  env_keep += KDN_ZELLIJ_SKIP
    Defaults  env_keep += TERMINAL_EMULATOR
  '';

  # One option, shared by every class that reads it. An import dedupes by path.
  declaration =
    { lib, ... }:
    {
      options.kdn.profile-headless.debugPolkit = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Turn the PAM U2F debug log on. The old module names this switch `debugPolkit`.
        '';
      };
    };
in
{
  kdn.profile-headless.includes = [
    kdn.dev-data
    kdn.hw-basic
    kdn.profile-headless-vim
    kdn.profile-headless-wezterm
    kdn.profile-headless-zellij
    kdn.program-atuin
    kdn.program-fish
    kdn.program-terminal-ide
    kdn.program-zsh
    kdn.toolset-essentials
    kdn.toolset-fs
    kdn.toolset-fs-encryption
    kdn.toolset-network
    kdn.toolset-nix
    kdn.toolset-unix
  ];

  kdn.profile-headless.nixos =
    { config, lib, ... }:
    {
      imports = [ declaration ];

      config = {
        boot.kernelParams = [
          "plymouth.enable=0" # no boot splash screen
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

        # `dbus` misbehaves together with a DynamicUser service.
        services.dbus.implementation = "broker";

        security.polkit.enable = true;
        security.pam.u2f.settings.debug = config.kdn.profile-headless.debugPolkit;

        security.sudo.extraConfig = sudoConfig;
        security.sudo-rs.extraConfig = sudoConfig;
      };
    };

  kdn.profile-headless.darwin =
    { ... }:
    {
      imports = [ declaration ];

      # nix-darwin declares `security.sudo.extraConfig` too
      # (`<nix-darwin>/modules/security/sudo.nix:14`), and it writes a `sudoers.d` drop-in.
      config.security.sudo.extraConfig = sudoConfig;
    };

  kdn.profile-headless.homeManager =
    { config, lib, ... }:
    {
      imports = [
        declaration
        ../common/persist.nix
      ];

      # The old module keeps every XDG user directory across a boot, and it puts the download
      # directory in the cache bucket instead. The computation reads the resolved session
      # variables, so it follows whatever the consumer sets.
      config =
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
        };
    };

  # The zellij leaf. A consumer that owns another multiplexer drops this one name.
  kdn.profile-headless-zellij.homeManager =
    { lib, ... }:
    {
      imports = [ ../common/persist.nix ];

      config = {
        programs.zellij.enable = true;
        programs.zellij.enableBashIntegration = true;
        # fish has its own auto-attach-to-`main` logic below instead of the generic home-manager
        # auto-start snippet: two zellij launchers in sequence mean that a detach from `main` falls
        # through into the second one, which starts a new unnamed session.
        programs.zellij.enableFishIntegration = false;
        programs.zellij.enableZshIntegration = true;
        programs.zellij.attachExistingSession = false; # do not attach to just any session

        # Auto-attach to the `main` session, but never over SSH: an SSH session lands in a plain
        # shell unless the user starts zellij by hand.
        #
        # Attach only when `main` has no client attached on THIS machine. That stops zellij from
        # opening in every terminal window: the first window attaches, and the next windows get a
        # plain shell. `zellij action list-clients` sees only a client of the local zellij server
        # (one server per machine), so a `main` open on a remote host over SSH does not count.
        #
        # `list-clients` always exits 0, so the state comes from stdout:
        #   - running + attached  -> a `CLIENT_ID ...` header plus one row per client
        #   - running + detached  -> the header alone
        #   - missing or EXITED   -> zellij prints the session list, with no `CLIENT_ID` header
        # So "attached here" means the header is present AND at least one client row follows.
        programs.fish.interactiveShellInit = ''
          if status is-interactive; and not set -q ZELLIJ; and not set -q SSH_CONNECTION; and not set -q SSH_TTY
            set -l kdn_zellij_clients (zellij --session main action list-clients 2>/dev/null)
            if string match --quiet 'CLIENT_ID*' -- $kdn_zellij_clients[1]; and test (count $kdn_zellij_clients) -gt 1
              # `main` is attached in another window on this machine; land in a plain shell.
            else
              zellij attach --create main
            end
          end
        '';

        kdn.disks.persist."usr/cache".directories = [ ".cache/zellij" ];

        programs.zellij.settings.scroll_buffer_size = 1 * 1000 * 1000;
        # TODO: a temporary measure — use the built-in theme instead of stylix.
        programs.zellij.settings.theme = "dracula";
        # fix Delete, which acts as Ctrl + H on an external keyboard
        programs.zellij.settings.support_kitty_keyboard_protocol = true;
      };
    };

  # The vim leaf. A consumer that owns another editor drops this one name.
  kdn.profile-headless-vim.homeManager =
    { lib, ... }:
    {
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
    };

  # The wezterm leaf. It writes one key-binding file, so Backspace sends 0x7F and not 0x08.
  kdn.profile-headless-wezterm.homeManager = {
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
  };
}
