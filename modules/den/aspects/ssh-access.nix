# The `ssh-access` slot, as a den aspect. It ports `modules/slots/ssh-access/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives a user topology-aware remote ssh access. The consumer describes a **host graph**: one
# entry per host, and one edge per route that reaches it. The `kdn-ssh-access` binary reads that
# graph, picks the cheapest route at connect time, and serves as the `ProxyCommand` for every
# `kdn-<name>` alias.
#
# The aspect emits one ssh drop-in file, `~/.ssh/config.d/40-kdn-ssh-access.config`. The binary is
# the single source of that file: `kdn-ssh-access emit-ssh-config` prints it, and the package's own
# `passthru.sshConfig` derivation captures the output. So the drop-in and the route logic can never
# disagree.
#
# The emitted `Host kdn-*` stanza carries four directives: `IdentityAgent SSH_AUTH_SOCK`, the
# `IdentityFile`, the `User` and the `ProxyCommand`. The `IdentityFile` comes from
# `kdn.ssh-access.defaults.identityFile`, and a host file sets it, because it names a machine-local
# hardware key. This aspect bakes no key path at all.
#
# ## The classes
#
# `homeManager` **and** `devenv`. The slot emits `home` and `devenv`, so this aspect declares both.
#
#   * `homeManager` writes the ssh drop-in and puts the binary on the user's PATH.
#   * `devenv` puts the binary and an `ssh-access` shim on the shell's PATH. It writes no file,
#     because a devenv shell owns no `$HOME`.
#
# The two classes share one option set. The declarations live in one module in this file's `let`, and
# both class modules import it, exactly as ./llm-proxy.nix shares one `optionsModule` between `nixos`
# and `devenv`. Each class is a separate evaluation, so one option path exists in both with no clash.
#
# ## The aspect holds no graph
#
# `kdn.ssh-access.hosts`, `.uplinks` and `.defaults` all default to a neutral value, so an adopter
# who supplies nothing gets an empty graph: no `kdn-<name>` alias, and a drop-in with the generic
# stanza alone. The consumer passes the real graph from its own host file, as a plain module.
#
# The creator's own graph stays out of this tree. It names real hosts, LAN and WAN addresses, ports
# and private DNS zones, so it is private configuration and never a default. The slot already works
# that way, and this port keeps it. See
# ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## The de-personalized default
#
# `defaults.user` defaults to one person's own login name in the shared schema file
# ../../../packages/kdn-ssh-access/module.nix. That file serves the slot route too, so a change to it
# would change an existing consumer's behaviour. This aspect neutralizes the value instead: it
# defines `defaults.user = lib.mkOverride 1400 null`.
#
# The priority number is not decoration. The module system turns an option's own `default` into a
# definition at priority 1500 — the same number `lib.mkOptionDefault` writes. The option type is
# `nullOr str`, and that type refuses to merge a null with a non-null value. So a `mkOptionDefault
# null` here meets the schema's `"kdn"` at equal priority and throws:
#
#   error: The option `kdn.ssh-access.defaults.user' is defined both null and not null
#
# Measured on 2026-09-10 against the one consumer that supplies no graph. Priority 1400 beats the
# schema's declaration default and still loses to a consumer's `lib.mkDefault`, which is 1000. A
# consumer's plain assignment, which is 100, wins as well.
#
# `null` writes no `User` directive, so `ssh` falls back to the local login name. A consumer that
# needs a fixed remote user names it.
#
# DECISION TO REVISE: the shared schema file keeps the personal default for the slot route. The two
# routes therefore disagree on one default until the slot tree goes away. See gap 6 of
# ../../../docs/tasks/2026-09/generalization/definition.md.
#
# ## The schema comes in by a relative path literal
#
# The slot reads the schema through `inputs.nix-configs + "/packages/kdn-ssh-access/module.nix"`, and
# that is a whole-tree store copy. The read below is a relative path literal, so the evaluation
# depends on one file. See
# ../../../docs/tasks/2026-09/generalization/011-whole-tree-store-copies/definition.md.
#
# Do **not** reach the schema through `pkgs.kdn.kdn-ssh-access.configModule`. `pkgs` is
# config-derived and this is an option **type**, so that route is an infinite recursion. The slot's
# own header records the same finding.
#
# DECISION TO REVISE: the option type reads a file two directories above this one. The aspect and the
# package are therefore coupled by path. A move of either one needs a matched edit until the package
# ships its schema through a flake output.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.ssh-access.enable` is gone, and
#    the empty graph default keeps the body a near no-op.
# 3. **No custom module argument.** Both target modules below take `config`, `lib` and `pkgs` only —
#    the arguments every NixOS, nix-darwin, home-manager and devenv evaluation already gives. The
#    slot reads `inputs` for the schema path; neither target here reads it.
{ ... }:
let
  # The shared option declarations. Both classes import this one module, so the two class trees hold
  # one identical option set and no declaration is ever copied.
  optionsModule =
    {
      lib,
      pkgs,
      ...
    }:
    {
      options.kdn.ssh-access = lib.mkOption {
        default = { };
        description = ''
          Topology-aware remote ssh access, as a host connectivity graph.

          The schema lives with the package, at `packages/kdn-ssh-access/module.nix`. It declares
          `defaults`, `identityAgentPatterns`, `uplinks` and `hosts`. This aspect adds `package` and
          it neutralizes the `defaults.user` default.

          Every value is the consumer's own. The aspect names no host, no address, no port and no
          key path.
        '';
        type = lib.types.submoduleWith {
          modules = [
            # A relative path literal, so the evaluation reads one file and not the whole tree.
            ../../../packages/kdn-ssh-access/module.nix

            (
              { config, ... }:
              {
                options.package = lib.mkOption {
                  type = lib.types.package;
                  description = "Configured kdn-ssh-access binary. It carries `.sshConfig` and `.accessConfig`.";
                  defaultText = lib.literalExpression "(pkgs.callPackage ../../../packages/kdn-ssh-access { }).withConfig { … }";
                  # A plain `callPackage` route, with no overlay. The slot reads
                  # `pkgs.kdn.kdn-ssh-access`, so a consumer must add this repository's `packages`
                  # overlay first. A relative path needs no overlay. ./jj.nix carries the same
                  # pattern.
                  default =
                    lib.throwIf (config.errors != [ ])
                      ("kdn.ssh-access: invalid edges:\n  " + lib.concatStringsSep "\n  " config.errors)
                      (
                        (pkgs.callPackage ../../../packages/kdn-ssh-access { }).withConfig {
                          inherit (config)
                            defaults
                            identityAgentPatterns
                            uplinks
                            hosts
                            ;
                        }
                      );
                };

                # Neutralize the personal default of the shared schema file.
                #
                # 1400 is deliberate, and `lib.mkOptionDefault` is wrong here. The module system
                # turns the schema's own `default = "kdn"` into a definition at priority 1500, and
                # `mkOptionDefault` writes 1500 too. The type is `nullOr str`, which refuses to merge
                # a null with a non-null value, so two definitions at 1500 throw. 1400 wins over the
                # schema default, and a consumer's `mkDefault` (1000) still wins over 1400. See the
                # header.
                config.defaults.user = lib.mkOverride 1400 null;
              }
            )
          ];
        };
      };
    };
in
{
  kdn.ssh-access.homeManager =
    {
      config,
      ...
    }:
    let
      cfg = config.kdn.ssh-access;
    in
    {
      imports = [ optionsModule ];

      # The ssh drop-in, plus the binary on the user's PATH. A `config.d` drop-in needs an `Include`
      # line in the user's own `~/.ssh/config`; the aspect writes no such line, exactly as the slot
      # writes none.
      #
      # DECISION TO REVISE: the file name starts with `40-` so a consumer can order its own drop-ins
      # around it. The number is the slot's own, and no option exposes it.
      config.home.file.".ssh/config.d/40-kdn-ssh-access.config".source = cfg.package.sshConfig;
      config.home.packages = [ cfg.package ];
    };

  kdn.ssh-access.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.ssh-access;

      # A short name for the one route a person types by hand. `kdn-ssh-access ssh <alias>` picks the
      # route and then execs `ssh`.
      #
      # DECISION TO REVISE: `ssh-access` is a generic name, so it can clash with another tool on the
      # shell's PATH. The slot chose it, and this port keeps it.
      sshAccessShim = pkgs.writeShellScriptBin "ssh-access" ''
        exec ${cfg.package}/bin/kdn-ssh-access ssh "$@"
      '';
    in
    {
      imports = [ optionsModule ];

      config.packages = [
        cfg.package
        sshAccessShim
      ];

      # The aspect's own smoke test. Every assertion stays offline: the build sandbox holds no
      # network, no real `$HOME` and no ssh server. So no assertion opens a connection.
      #
      # `emit-ssh-config` prints the drop-in and reads no network. It is the one safe command here;
      # `kdn-ssh-access debug` opens real sessions, so it never belongs in a test.
      config.enterTest = ''
        echo "• ssh-access: the emitted drop-in carries the generic stanza" >&2
        kdn-ssh-access emit-ssh-config | grep -Fq 'Host kdn-*'

        echo "• ssh-access: the generic stanza pins the agent and names a ProxyCommand" >&2
        kdn-ssh-access emit-ssh-config | grep -Fq 'IdentityAgent SSH_AUTH_SOCK'
        kdn-ssh-access emit-ssh-config | grep -Fq 'ProxyCommand'

        echo "• ssh-access: the short shim is executable" >&2
        test -x ${lib.getExe sshAccessShim}
      '';
    };
}
