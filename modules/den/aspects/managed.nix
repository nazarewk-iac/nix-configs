# A cleanup pass for a generated file, as a den aspect. It ports
# `modules/universal/managed/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# A module writes a file into a real directory, not into the store — a rendered secret is one
# example. When the module stops writing that file, the file stays on disk. This aspect deletes such
# a leftover on every activation.
#
# It keeps a file that `currentFiles` names. It deletes every other file that a name in `infix`
# matches, inside each directory in `directories`, between `mindepth` and `maxdepth`.
#
# ## Two classes, one body
#
# The `nixos` class and the `darwin` class need the same options and the same script, and they differ
# only in the activation hook. So the `let` below builds one target module, and a flag picks the
# hook. The two classes are separate module systems, so the duplicate option declaration is safe.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old default follows `directories != [ ]`, so a
#    consumer with no directory got no script. The script with no directory only prints one line, so
#    the aspect runs it unconditionally.
# 2. Nothing else. Every emitted value matches the old module.
#
# ## What it reads from another aspect
#
# `config.kdn.security.secrets.allowed or true` and `config.sops.templates or { }` — the policy leaf
# and the template set of `./secrets.nix`. Both `or` fallbacks keep this aspect standalone: a
# consumer that includes no `secrets` aspect declares neither name, and each read yields the
# fallback. Deferred decision D2 permits the read.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  mkTarget =
    { onDarwin }:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.managed;
    in
    {
      options.kdn.managed.infix = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          The name parts that mark a file as managed. The cleanup deletes a file whose name holds
          one of these parts.
        '';
      };

      options.kdn.managed.directories = lib.mkOption {
        # TODO: switch to submodule with min/max depth
        type =
          let
            directoryType = lib.types.submodule (
              { name, ... }@args:
              {
                options.path = lib.mkOption {
                  type = lib.types.path;
                  default = args.name;
                  defaultText = lib.literalExpression "the attribute name";
                  description = "The directory the cleanup searches.";
                };
                options.mindepth = lib.mkOption {
                  type = lib.types.ints.u8;
                  default = 1;
                  description = "The lowest depth the cleanup searches.";
                };
                options.maxdepth = lib.mkOption {
                  type = lib.types.ints.u8;
                  default = 1;
                  description = "The highest depth the cleanup searches.";
                };
              }
            );
            coerce = value: (coercers."${builtins.typeOf value}") value;
            coercers = {
              string = value: coercers.set { path = value; };
              set = value: if value ? path then { "${value.path}" = value; } else value;
              list =
                value:
                lib.pipe value [
                  (map (
                    value:
                    lib.pipe value [
                      coerce
                      builtins.attrValues
                      builtins.head
                      (coerced: {
                        name = coerced.path;
                        value = coerced;
                      })
                    ]
                  ))
                  builtins.listToAttrs
                ];
            };
          in
          lib.types.coercedTo (lib.types.oneOf [
            (lib.types.listOf lib.types.str)
            (lib.types.listOf directoryType)
            (lib.types.attrsOf directoryType)
          ]) coerce (lib.types.attrsOf directoryType);
        default = [ ];
        description = ''
          The directories the cleanup searches. A plain string, a list or an attribute set all
          work; the type coerces each one to an attribute set.
        '';
      };

      options.kdn.managed.currentFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "The files the cleanup keeps. Every other managed file goes.";
      };

      options.kdn.managed.scripts.cleanup = lib.mkOption {
        type = lib.types.package;
        description = "The script that deletes every leftover managed file.";
        default = pkgs.writeShellApplication {
          name = "kdn-managed-cleanup";
          text =
            let
              mkExistingArgs =
                dir:
                lib.pipe cfg.currentFiles [
                  lib.lists.unique
                  (builtins.filter (lib.strings.hasPrefix dir))
                  (map (p: [
                    "!"
                    "-path"
                    p
                  ]))
                  lib.lists.flatten
                ];

              infixArgs = lib.pipe cfg.infix [
                builtins.attrValues
                lib.lists.unique
                (map (infix: [
                  "-name"
                  "*${infix}*"
                ]))
                (lib.foldl (a: b: a ++ lib.optional (a != [ ] && b != [ ]) "-o" ++ b) [ ])
                (x: if x == [ ] then [ ] else [ "(" ] ++ x ++ [ ")" ])
              ];

              mkDelDirCmd = dirCfg: ''
                ${lib.getExe pkgs.findutils} \
                  ${dirCfg.path} \
                  -mindepth ${toString dirCfg.mindepth} -maxdepth ${toString dirCfg.maxdepth} \
                  -type f \
                  ${lib.escapeShellArgs infixArgs} \
                  ${lib.escapeShellArgs (mkExistingArgs dirCfg.path)} \
                  -printf '> removed: %p\n' -delete
              '';

              delCmds = lib.pipe cfg.directories [
                builtins.attrValues
                (map mkDelDirCmd)
                (builtins.concatStringsSep "\n")
              ];
            in
            ''
              echo 'Cleaning up managed files...'
              ${delCmds}
            '';
        };
      };

      config = lib.mkMerge [
        {
          kdn.managed.infix.default = "kdn-managed-3b48ebd3";
        }
        (lib.mkIf (!onDarwin) {
          system.activationScripts.kdnManagedFilesCleanup.text = lib.getExe cfg.scripts.cleanup;
          system.activationScripts.kdnManagedFilesCleanup.deps = [
            "etc"
            "users"
          ];
        })
        (lib.mkIf onDarwin {
          system.activationScripts.postActivation.text = lib.mkAfter (lib.getExe cfg.scripts.cleanup);
        })
        (lib.mkIf (config.kdn.security.secrets.allowed or true) {
          kdn.managed.currentFiles = lib.pipe (config.sops.templates or { }) [
            builtins.attrValues
            (map (tpl: tpl.path))
          ];
        })
      ];
    };
in
{
  kdn.managed.nixos = mkTarget { onDarwin = false; };

  kdn.managed.darwin = mkTarget { onDarwin = true; };
}
