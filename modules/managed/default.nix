{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.managed;
in
{
  options.kdn.managed = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.directories != [ ];
    };

    infix = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
    };

    directories = lib.mkOption {
      # TODO: switch to submodule with min/max depth
      type =
        let
          directoryType = lib.types.submodule ({ name, ... }@args: {
            options.path = lib.mkOption {
              type = with lib.types; path;
              default = args.name;
            };
            options.mindepth = lib.mkOption {
              type = with lib.types; ints.u8;
              default = 1;
            };
            options.maxdepth = lib.mkOption {
              type = with lib.types; ints.u8;
              default = 1;
            };
          });
          coerce = value: (coercers."${builtins.typeOf value}") value;
          coercers = {
            string = value: coercers.set { path = value; };
            set = value: if value ? path then { "${value.path}" = value; } else value;
            list = value: lib.pipe value [
              (builtins.map (value: lib.pipe value [
                coerce
                builtins.attrValues
                builtins.head
                (coerced: { name = coerced.path; value = coerced; })
              ]))
              builtins.listToAttrs
            ];
          };
        in
        with lib.types; (coercedTo
          (oneOf [ (listOf str) (listOf directoryType) (attrsOf directoryType) ])
          coerce
          (attrsOf directoryType)
        );
      default = [ ];
    };

    currentFiles = lib.mkOption {
      type = with lib.types; listOf path;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.managed.infix.default = "kdn-managed-3b48ebd3";
      system.activationScripts.setupSecrets.deps = [ "kdnManagedFilesCleanup" ];
      system.activationScripts.kdnManagedFilesCleanup.text =
        let
          mkExistingArgs = dir: lib.pipe cfg.currentFiles [
            lib.lists.unique
            (builtins.filter (lib.strings.hasPrefix dir))
            (builtins.map (path: [ "!" "-path" path ]))
            lib.lists.flatten
          ];

          infixArgs = lib.pipe cfg.infix [
            builtins.attrValues
            lib.lists.unique
            (builtins.map (infix: [ "-name" "*${infix}*" ]))
            (lib.foldl (a: b: a ++ lib.optional (a != [ ] && b != [ ]) "-o" ++ b) [ ])
            (x: if x == [ ] then [ ] else [ "(" ] ++ x ++ [ ")" ])
          ];

          mkDelDirCmd = dirCfg: ''
            ${lib.getExe pkgs.findutils} \
              ${dirCfg.path} \
              -mindepth ${builtins.toString dirCfg.mindepth} -maxdepth ${builtins.toString dirCfg.maxdepth} \
              -type f \
              ${lib.escapeShellArgs infixArgs} \
              ${lib.escapeShellArgs (mkExistingArgs dirCfg.path)} \
              -printf '> removed: %p\n' -delete
          '';

          delCmds = lib.pipe cfg.directories [
            builtins.attrValues
            (builtins.map mkDelDirCmd)
            (builtins.concatStringsSep "\n")
          ];
        in
        ''
          echo 'Cleaning up managed files...'
          ${delCmds}
        '';
    }
    (lib.mkIf config.kdn.security.secrets.enable {
      kdn.managed.currentFiles = lib.pipe config.sops.templates [
        builtins.attrValues
        (builtins.map (tpl: tpl.path))
      ];
    })
  ]);
}
