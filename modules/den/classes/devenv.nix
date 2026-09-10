# A den class for a devenv shell.
#
# den ships no devenv class. It declares `nixos` and `darwin` only; `homeManager`, `hjem`, `maid`,
# `wsl`, `flake-parts`, `os` and `user` come from batteries. 13 of this repo's 18 slots target
# devenv, so den needs this class before it can hold them.
#
# devenv is a plain `lib.evalModules` target. The entry module is
# `<devenv>/src/modules/top-level.nix`. `specialArgs.inputs` is mandatory and may be empty.
# `devenv.root` and `devenv.tmpdir` are mandatory and carry no default. The shell is at
# `config.shell`. It needs no `--impure`, no devenv CLI and no CppNix-only builtin. Measured on
# 2026-09-10 — see 004-den-spike/research.md, criterion 1.
#
# The class serves two routes:
#
#   1. Every den host also produces a shell, through `den.policies.host-to-devenv`. This is the
#      real repository shape: one host, one shell, one aspect list.
#   2. A standalone shell that belongs to no host. It calls `den.lib.aspects.resolve "devenv"` on
#      each aspect and passes the results to `kdn.den.devenv.mkShell`. It declares no den entity.
#      See ../../../checks/den-mvp/devenv/default.nix.
{
  den,
  inputs,
  lib,
  config,
  ...
}:
let
  cfg = config.kdn.den.devenv;

  # One devenv evaluation. Both routes below call it, so they cannot drift apart.
  mkShell =
    {
      name,
      system,
      modules,
    }:
    (lib.evalModules {
      class = "devenv";
      specialArgs.inputs = { };
      modules = [
        (inputs.devenv.outPath + "/src/modules/top-level.nix")
        {
          _module.args.pkgs = import inputs.nixpkgs { inherit system; };
          devenv.root = cfg.root;
          devenv.tmpdir = "/tmp";
          inherit name;
        }

        # A module function, not a plain attrset: this `config` must be the devenv evaluation's own,
        # not the den `config` that the outer function closes over.
        #
        # These shells are built. The devenv CLI never drives them. devenv's `tasks` module gates a
        # bash prelude on `devenv.cli.version`: a null or a pre-2.0 value prepends
        # `devenv-tasks run devenv:enterTest` to `enterTest`. That binary needs a writable
        # `devenv.dotfile` and a task source, and a build sandbox gives it neither — a smoke test
        # then fails with `Error: NoSource`. Pinning the version to the module tree's own version
        # drops the prelude, so `config.test` holds the plain assertions.
        #
        # It also silences the CLI-versus-modules mismatch warning, because the two now agree.
        # `<devenv>/src/modules/tasks.nix:476,486` and `update-check.nix:55,76`. Measured on
        # 2026-09-10.
        (
          { config, ... }:
          {
            devenv.cli.version = lib.mkDefault config.devenv.latestVersion;
          }
        )
      ]
      ++ modules;
    }).config;
in
{
  # den declares one `flake.<output>` option per output name it knows. `devenvShells` is not one of
  # them, so this class declares its own. Without the declaration the whole evaluation fails with
  # `The option 'flake.devenvShells' does not exist`.
  options.flake.devenvShells = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "One evaluated devenv configuration per den host and per standalone shell.";
  };

  options.kdn.den.devenv.root = lib.mkOption {
    type = lib.types.str;
    default = "/den-mvp";
    description = ''
      Value for devenv's own mandatory `devenv.root` option. devenv declares no default for it.

      The default is a placeholder, because these shells build and never run interactively. A real
      interactive shell needs the real working directory, and the devenv CLI passes that itself.

      **The value must not be a store path.** devenv's `claude.code` integration writes
      `files."''${devenv.root}/.claude/settings.json"`, which makes the root a *dynamic attribute
      name*. Nix rejects such a name when it refers to a store path:

        error: the string '/nix/store/…-source/.claude/settings.json' is not allowed to refer to a
        store path

      So `"''${self}"` cannot be the value. Measured on 2026-09-10 against
      `<devenv>/src/modules/integrations/claude.nix:977`.
    '';
  };

  options.kdn.den.devenv.mkShell = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = ''
      Evaluate one devenv configuration. The standalone route calls it directly, and the
      `host-to-devenv` policy calls it as a host's `instantiate`.

      `name` and `system` are arguments because den calls `instantiate` with `{ modules }` and
      nothing else. Measured on 2026-09-10 with a probe entity.

      Do not wrap this in a helper that returns a whole den module. A den module whose **keys**
      come from `config` is an infinite recursion: the module system must read `config` to learn
      which options the module defines, and `config` needs every module first. Keep the keys
      static and read `config` in the values only.
    '';
  };

  config = {
    den.classes.devenv = { };

    kdn.den.devenv.mkShell = mkShell;

    # host → devenv shell. Every den host gets one shell from its own aspect list.
    den.policies.host-to-devenv =
      { host, ... }:
      [
        (den.lib.policy.instantiate {
          name = "${host.name}-devenv";
          class = "devenv";
          instantiate =
            { modules, ... }:
            mkShell {
              name = "${host.name}-devenv";
              inherit (host) system;
              inherit modules;
            };
          intoAttr = [
            "devenvShells"
            host.name
          ];
        })
      ];

    den.schema.host.includes = [ den.policies.host-to-devenv ];
  };
}
