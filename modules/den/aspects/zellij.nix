# The `zellij` slot, as a den aspect. It ports `modules/slots/zellij/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs zellij and two helper packages, two Claude Code hooks, a read-only Bash allowlist,
# and one agent skill. The skill holds one rule: an agent never changes and never reads the user's
# own zellij session. The agent runs its own work in a dedicated background session instead.
#
# The allowlist covers three shapes only:
#
#  1. Pure discovery. It reveals no pane content and it changes no state.
#  2. The creation of the agent's **own** detached session. It is idempotent.
#  3. One exact command, with no wildcard, that dumps the last line of the agent's **own** pane.
#     Claude Code matches the literal command text, before the shell expands `$ZELLIJ_PANE_ID`. So
#     this rule can never match a hardcoded pane number or another command shape.
#
# It deliberately holds no content read of another pane (`dump-screen -p <other>`, `subscribe`,
# `edit-scrollback`) and no mutating action (`new-pane`, `new-tab`, `go-to-tab*`, `focus-pane-id`,
# `close-*`, `kill-session`, `delete-session`, `write*`, `paste`, `send-keys`). Each of those stays
# behind a normal permission prompt, so the user answers every time.
#
# ## The two hooks
#
# `zellij-wait-for-devenv` delays a Bash tool call while devenv rebuilds in the same zellij pane.
# It is an instant no-op outside zellij and devenv, and also when devenv is idle.
#
# `zellij-wait-for-devenv-start` polls for up to about one second after a file write, until
# devenv's watcher starts a rebuild. It closes one race: a Bash call that fires directly after a
# write reads a stale "devenv ready" state, and then the hook above skips its wait. This hook always
# continues afterwards. It never waits for the rebuild to finish.
#
# ## Three ports that differ from the slot
#
#  1. **The helper packages come from `pkgs.callPackage`.** The slot reads `pkgs.kdn.kdn-slug` and
#     `pkgs.kdn.zellij-llm`, so it needs this repository's `packages` overlay. A den consumer
#     supplies a plain `pkgs`, so this aspect calls the package directory itself. `zellij-llm` takes
#     `kdn-slug` as a plain argument for exactly this reason.
#  2. **Each repository file is a relative path literal.** The slot writes
#     `"${inputs.nix-configs}/…"`. That is a second whole-tree fetch, and an edit to any unrelated
#     file invalidates it. A relative literal stays inside the tree the evaluation already reads, so
#     it adds no fetch and no second copy. See
#     ../../../docs/tasks/2026-09/generalization/011-whole-tree-store-copies/definition.md.
#  3. **`kdn.isSourceRepo` arrives through an import by path.** See ../common/source-repo.nix.
#
# ## Where the two shell scripts live
#
# This aspect reads `wait-for-devenv.sh` and `wait-for-devenv-start.sh` from `hack/`, and so does
# the slot. One copy each, two relative path literals each, so no duplicate can drift. A retirement
# of `modules/slots/` needs no script rescue. `hack/flake-update-complete.sh` set the precedent. See
# ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
#    An argument such as `inputs` would force the consumer to pass `specialArgs`.
#
# ## The web aspect
#
# `kdn.zellij-web` adds the built-in zellij web interface. It includes `kdn.zellij`, so it carries
# the base configuration too. The interface is a systemd user service on Linux, and it binds
# loopback by default. A consumer sets `kdn.zellij.web.*`: `bindAddress`, `port`, `certFile`,
# `keyFile`, `keySopsFile`, `user` and `firewallInterfaces`.
#
# The aspect declares no `enable` option. Inclusion is the switch, as rule 2 states. The `web`
# options hold no `enable` either, so the standalone check finds no reachable one.
#
# The `nixos` target opens the port on each named interface and decrypts a SOPS key when one is
# named. The `homeManager` target writes the user service when `certFile` is set.
{ kdn, ... }:
let
  # The shared web option declarations. Both `zellij-web` targets import this one module, so the
  # `nixos` tree and the `homeManager` tree hold one identical option set. The declarations carry
  # no `enable`: inclusion of the aspect is the switch.
  optionsModule =
    { lib, ... }:
    {
      options.kdn.zellij.web = {
        bindAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          example = "0.0.0.0";
          description = ''
            Address the web server binds. The default keeps it on loopback. Set `0.0.0.0` to
            expose it, and open the port with `firewallInterfaces`.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8082;
          description = "TCP port of the web server.";
        };

        certFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "PEM certificate the web server serves. Required off loopback.";
        };

        keyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            PEM private key of `certFile`. It must be readable by the user that runs the web
            server. When `keySopsFile` is set and this is null, the module decrypts the key to a
            user-readable path and uses that path.
          '';
        };

        keySopsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            SOPS-encrypted (raw/binary) private key. A system service decrypts it into
            `/run/secrets/kdn/zellij/<hostName>.key`, owned by `user`, mode 0400. Set `user`.
          '';
        };

        user = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OS user that runs the web server and owns the decrypted key.";
        };

        firewallInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "nb-priv" ];
          description = "Interfaces whose firewall opens `port`.";
        };
      };
    };
in
{
  kdn.zellij.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.zellij;

      kdn-slug = pkgs.callPackage ../../../packages/llm/kdn-slug { };
      zellij-llm = pkgs.callPackage ../../../packages/llm/zellij-llm { inherit kdn-slug; };

      waitForDevenv = pkgs.writeShellApplication {
        name = "zellij-wait-for-devenv";
        runtimeInputs = [
          pkgs.jq
          pkgs.gawk
        ];
        text = builtins.readFile ../../../hack/wait-for-devenv.sh;
      };

      waitForDevenvStart = pkgs.writeShellApplication {
        name = "zellij-wait-for-devenv-start";
        runtimeInputs = [
          pkgs.jq
          pkgs.gawk
        ];
        text = builtins.readFile ../../../hack/wait-for-devenv-start.sh;
      };
    in
    {
      imports = [ ../common/source-repo.nix ];

      options.kdn.zellij.installAgentRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install this aspect's agent instruction file into the consumer repository.

          The file is `.claude/skills/zellij/SKILL.md`. It states the author's own mandate: an agent
          never reads and never changes the user's own zellij session. The default is false, so you
          get the file only when you ask for it. This repository turns the option on explicitly in
          `checks/den-mvp/devenv/default.nix`.

          The option covers the instruction file only. The packages, the two hooks and the Bash
          allowlist stay in place.
        '';
      };

      config = {
        packages = [
          pkgs.zellij
          kdn-slug
          zellij-llm
        ];

        claude.code.enable = lib.mkDefault true;

        claude.code.hooks.zellij-wait-for-devenv = {
          hookType = "PreToolUse";
          matcher = "Bash";
          command = lib.getExe waitForDevenv;
        };

        claude.code.hooks.zellij-wait-for-devenv-start = {
          hookType = "PostToolUse";
          matcher = "^(Edit|MultiEdit|Write)$";
          command = lib.getExe waitForDevenvStart;
        };

        # Read-only discovery. It reveals no pane content and it changes no session, tab or pane
        # state. Each rule matches with no `--session` (the agent's own attached session) and with an
        # explicit `--session <name>`.
        claude.code.permissions.rules.Bash.allow = [
          "zellij --help"
          "zellij help*"
          "zellij * --help"
          "zellij list-sessions*"
          "zellij action list-panes *"
          "zellij --session * action list-panes *"
          "zellij action list-tabs *"
          "zellij --session * action list-tabs *"
          "zellij action list-clients*"
          "zellij --session * action list-clients*"
          "zellij action current-tab-info*"
          "zellij --session * action current-tab-info*"
          # Idempotent. It creates the agent's own detached session when none exists, and it is a
          # no-op otherwise. It never reaches a session that a user attached.
          "zellij attach --create-background *"
          # Exact and static, with no wildcard. It always names the agent's own pane, for example to
          # read the last status line of an asynchronous devenv rebuild.
          ''zellij action dump-screen -p "$ZELLIJ_PANE_ID" | tail -n 1''
        ];

        # One file, not a whole tree. See rule 2 in the header.
        files = lib.mkIf (cfg.installAgentRules && !config.kdn.isSourceRepo) {
          ".claude/skills/zellij/SKILL.md".source = ../../../.agents/skills/zellij/SKILL.md;
        };

        # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
        #
        # devenv puts this in `config.enterTest` (`types.lines`, so several aspects merge). It runs
        # under `devenv test` and under `checks.<system>.den-smoke-*`. It never runs on shell entry,
        # and it never runs during a nix-darwin or a NixOS activation.
        #
        # Every assertion stays offline. The check runs inside the build sandbox, which has no
        # network, no real `$HOME` and no zellij server. So no assertion starts a session.
        enterTest = ''
          echo "• zellij: the binary reports a version" >&2
          zellij --version | grep -qE '^zellij [0-9]+\.'

          echo "• zellij: kdn-slug parses its arguments" >&2
          kdn-slug --help >/dev/null

          echo "• zellij: zellij-llm lists its subcommands" >&2
          zellij-llm --help 2>&1 | grep -qE 'spawn'
        '';
      };
    };

  # The Home Manager zellij configuration. It is the same body as the universal module, so the two
  # trees cannot drift. It imports `../common/persist.nix` for the two `kdn.disks.persist` buckets it
  # writes. It does not import `optionsModule`: it declares no web option.
  kdn.zellij.homeManager =
    {
      config,
      lib,
      ...
    }:
    {
      imports = [ ../common/persist.nix ];

      config = {
        programs.zellij.enable = true;
        programs.zellij.enableBashIntegration = true;
        # fish has its own auto-attach-to-`main` logic below instead of the generic
        # home-manager auto-start snippet: enabling both stacks two zellij-launchers in
        # sequence, so quitting/detaching from `main` falls through into the second one
        # spawning a brand new unnamed session.
        programs.zellij.enableFishIntegration = false;
        programs.zellij.enableZshIntegration = true;
        programs.zellij.attachExistingSession = false; # don't attach to just any session

        # auto-attach to `main` session, but never over SSH: SSH sessions should land in a
        # plain shell unless zellij is invoked explicitly.
        #
        # Attach only when `main` has no client attached on THIS machine. This stops zellij
        # from opening in every terminal window: the first window attaches, the next windows
        # get a plain shell. `zellij action list-clients` sees only clients on the local
        # zellij server (one server per machine), so a `main` open on a remote host over SSH
        # is a separate server and does not count here.
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
        # The web server keeps its login tokens here.
        kdn.disks.persist."usr/data".directories = [ ".local/share/zellij" ];
        programs.zellij.settings.scroll_buffer_size = 1 * 1000 * 1000;
        # TODO: this is "temporary" measure to use built-in theme instead of stylix
        programs.zellij.settings.theme = "dracula";
        # fix Delete working as Ctrl + H on external keyboard
        programs.zellij.settings.support_kitty_keyboard_protocol = true;
      };
    };

  # The web interface. It includes the base aspect, so it carries the configuration above too.
  kdn.zellij-web.includes = [ kdn.zellij ];

  # The user service. It runs on Linux only, and it needs a certificate. A missing key is not fatal
  # at start: the unit restarts until the decrypt service or the consumer supplies it.
  kdn.zellij-web.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.zellij;

      # The key the user service reads. A host that sets `keyFile` names its own path; a host that
      # sets `keySopsFile` gets the decrypted copy.
      webKeyPath =
        if cfg.web.keyFile != null then
          cfg.web.keyFile
        else
          "/run/secrets/kdn/zellij/${config.kdn.hostName}.key";
    in
    {
      imports = [
        optionsModule
        ../common/host-name.nix
      ];

      config = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.web.certFile != null) {
        systemd.user.services.zellij-web = {
          Unit = {
            Description = "Zellij web interface";
            After = [ "network.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe config.programs.zellij.finalPackage)
              "web"
              "--start"
              "--ip"
              cfg.web.bindAddress
              "--port"
              (toString cfg.web.port)
              "--cert"
              cfg.web.certFile
              "--key"
              webKeyPath
            ];
            # The key may not exist yet at first start; retry.
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };

  # The system side. It opens the port on each named interface, and it decrypts a SOPS key when one
  # is named. Both halves are inert when the consumer names neither.
  kdn.zellij-web.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.zellij;
    in
    {
      imports = [
        optionsModule
        ../common/host-name.nix
      ];

      config = lib.mkMerge [
        (lib.mkIf (cfg.web.firewallInterfaces != [ ]) {
          networking.firewall.interfaces = lib.genAttrs cfg.web.firewallInterfaces (_: {
            allowedTCPPorts = [ cfg.web.port ];
          });
        })
        (lib.mkIf (cfg.web.keySopsFile != null) {
          systemd.services.kdn-zellij-web-key = {
            description = "Decrypt the zellij web TLS private key into /run/secrets";
            wantedBy = [ "multi-user.target" ];
            path = [
              pkgs.sops
              pkgs.coreutils
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "root";
              Group = "root";
            };
            script = ''
              set -euo pipefail
              mkdir -p /run/secrets/kdn/zellij
              ${pkgs.sops}/bin/sops decrypt --output-type binary \
                ${cfg.web.keySopsFile} > /run/secrets/kdn/zellij/${config.kdn.hostName}.key
              chown ${cfg.web.user} /run/secrets/kdn/zellij/${config.kdn.hostName}.key
              chmod 0400 /run/secrets/kdn/zellij/${config.kdn.hostName}.key
            '';
          };
        })
      ];
    };
}
