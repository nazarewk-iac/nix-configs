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
{
  den,
  inputs,
  lib,
  config,
  ...
}:
{
  # den declares one `flake.<output>` option per output name it knows. `devenvShells` is not one of
  # them, so this class declares its own. Without the declaration the whole evaluation fails with
  # `The option 'flake.devenvShells' does not exist`.
  options.flake.devenvShells = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "One evaluated devenv configuration per den host.";
  };

  options.kdn.den.devenv.root = lib.mkOption {
    type = lib.types.str;
    description = ''
      Value for devenv's own mandatory `devenv.root` option. devenv declares no default for it.

      A flake output cannot know the directory the user stands in, so this holds the flake's own
      store path. A real interactive shell needs the real working directory, and the devenv CLI
      passes that itself.
    '';
  };

  config = {
    den.classes.devenv = { };

    # host → devenv shell. Every den host also produces one shell, so one entity and one aspect list
    # serve both targets.
    den.policies.host-to-devenv =
      { host, ... }:
      [
        (den.lib.policy.instantiate {
          name = "${host.name}-devenv";
          class = "devenv";
          instantiate =
            { modules, ... }:
            (lib.evalModules {
              class = "devenv";
              specialArgs.inputs = { };
              modules = [
                (inputs.devenv.outPath + "/src/modules/top-level.nix")
                {
                  _module.args.pkgs = import inputs.nixpkgs { system = host.system; };
                  devenv.root = config.kdn.den.devenv.root;
                  devenv.tmpdir = "/tmp";
                  name = "${host.name}-devenv";
                }
              ]
              ++ modules;
            }).config;
          intoAttr = [
            "devenvShells"
            host.name
          ];
        })
      ];

    den.schema.host.includes = [ den.policies.host-to-devenv ];
  };
}
