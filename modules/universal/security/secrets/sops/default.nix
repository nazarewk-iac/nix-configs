{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.security.secrets.sops;

  sopsPlaceholderPattern = {
    name ? "",
    path ? "",
    hash ?
      if name != ""
      then builtins.substring 0 8 (builtins.hashString "sha256" name)
      else "",
    infix ? "${path}:${hash}",
  }: "<SOPS:${infix}:PLACEHOLDER>";

  # adds additional information (name) to sops-nix placeholders
  # replaces https://github.com/Mic92/sops-nix/blob/be0eec2d27563590194a9206f551a6f73d52fa34/modules/sops/templates/default.nix#L84-L84
  sopsPlaceholders =
    builtins.mapAttrs (
      name: secretCfg:
        sopsPlaceholderPattern {
          inherit name;
          inherit (secretCfg) path;
        }
    )
    config.sops.secrets;
in {
  options.kdn.security.secrets.sops = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = config.kdn.security.secrets.enable;
    };
    files = lib.mkOption {
      default = {};
      type = lib.types.attrsOf (
        lib.types.submodule (
          {name, ...} @ fargs: let
            fileCfg = fargs.config;
          in {
            options.namePrefix = lib.mkOption {
              type = with lib.types; str;
              default = fargs.name;
            };
            options.keyPrefix = lib.mkOption {
              type = with lib.types; str;
              default = "";
              apply = value:
                lib.pipe value [
                  (lib.strings.removeSuffix "/")
                  (v:
                    if v != ""
                    then "${v}/"
                    else v)
                ];
            };
            options.sopsFile = lib.mkOption {
              type = with lib.types; path;
            };
            options.basePath = lib.mkOption {
              type = with lib.types; nullOr path;
              default = null;
            };
            options.sops = lib.mkOption {
              type = with lib.types; attrsOf anything;
              default = {};
            };
            options.overrides = lib.mkOption {
              type = with lib.types; listOf anything;
              default = [];
            };
            options.discovered.keys = lib.mkOption {
              readOnly = true;
              type = with lib.types; listOf str;
              default = lib.pipe fileCfg.sopsFile [
                lib.kdn.sops.parseSopsYAMLMetadata
                (builtins.map (e: builtins.concatStringsSep "/" e.path))
                (builtins.filter (lib.strings.hasPrefix fileCfg.keyPrefix))
              ];
            };
            options.discovered.entries = lib.mkOption {
              readOnly = true;
              default = lib.pipe fileCfg.discovered.keys [
                (builtins.map (path: {
                  name = "${fileCfg.namePrefix}/${lib.strings.removePrefix fileCfg.keyPrefix path}";
                  value =
                    fileCfg.sops
                    // {
                      sopsFile = fileCfg.sopsFile;
                      key = path;
                    }
                    // (
                      if fileCfg.basePath != null
                      then {
                        path = "${fileCfg.basePath}/${path}";
                      }
                      else {}
                    );
                }))
                builtins.listToAttrs
                (builtins.mapAttrs (
                  name: secretCfg:
                    lib.lists.foldl' (old: override: old // override name old) secretCfg fileCfg.overrides
                ))
              ];
            };
          }
        )
      );
    };

    placeholders = lib.mkOption {
      description = ''converts `sops.placeholders` into object structure to iterate more easily over it'';
      readOnly = true;
      type = with lib.types; anything;

      # avoids `error: infinite recursion encountered` by not referencing `config.sops.templates` and re-implementing placeholder
      default = lib.pipe config.sops.secrets [
        builtins.attrNames
        (builtins.map (
          name: lib.attrsets.setAttrByPath (lib.strings.splitString "/" name) sopsPlaceholders."${name}"
        ))
        # dumb merge
        (builtins.foldl' lib.attrsets.recursiveUpdate {})
      ];
    };

    secrets = lib.mkOption {
      description = ''converts `sops.secrets` into object structure to iterate more easily over it'';
      readOnly = true;
      type = with lib.types; anything;

      default = lib.pipe config.sops.secrets [
        (lib.attrsets.mapAttrsToList (
          name: value: lib.attrsets.setAttrByPath (lib.strings.splitString "/" name) value
        ))
        # dumb merge
        (builtins.foldl' lib.attrsets.recursiveUpdate {})
      ];
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifTypes ["nixos" "darwin"] (lib.mkMerge [
      {
        nixpkgs.overlays = [
          (final: prev: {
            jsonTemplate = let
              json = final.formats.json {};
              prefix = "<UNWRAP:";
              suffix = ":UNWRAP>";
            in {
              inherit (json) type;
              unwrap = txt: "${prefix}${txt}${suffix}";
              /*
              original https://github.com/NixOS/nixpkgs/blob/25494c1d30252a0a58913be296da382fdcc631eb/pkgs/pkgs-lib/formats.nix#L64-L71
              allows unwrapping of string values into raw types
              */
              generate = name: value:
                lib.pipe value [
                  (json.generate "${name}.wrapped.json")
                  builtins.readFile
                  (builtins.replaceStrings ["\"${prefix}" "${suffix}\""] ["" ""])
                  (pkgs.writeText name)
                ];
            };
            kdn =
              (prev.kdn or {})
              // {
                kdn-sops-secrets = let
                  pattern = sopsPlaceholderPattern {
                    path = "(?P<path>[^:]+)";
                    hash = "(?P<hash>[^:]+)";
                  };
                  r.pattern = ''pattern: str = ""'';
                  replacements = {
                    "${r.pattern}" = ''pattern = r"${pattern}"'';
                  };
                in
                  final.writers.writePython3Bin "kdn-sops-secrets"
                  {
                    libraries = with pkgs.python3Packages; [
                      fire
                    ];
                  }
                  (
                    lib.pipe ./kdn-sops-secrets.py [
                      builtins.readFile
                      (builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements))
                    ]
                  );
              };
          })
        ];
        kdn.env.packages = [
          pkgs.sops
          pkgs.kdn.kdn-sops-secrets
        ];

        sops.placeholder = sopsPlaceholders;
      }
      (lib.mkIf config.kdn.security.secrets.allow {
        sops.templates."placeholder.txt".content = ""; # fills-in `sops.placeholder`
        sops.secrets = lib.pipe cfg.files [
          builtins.attrValues
          (builtins.map (fileCfg: fileCfg.discovered.entries))
          lib.mkMerge
        ];
      })
    ]))
    (kdnConfig.util.ifTypes ["nixos"] (lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.services.userborn.enable || config.services.sysusers.enable;
            message = "either `services.{userborn,sysusers}.enable` must be enabled for `sops-nix` to integrate into the system properly";
          }
        ];
      }
      {
        systemd.targets.kdn-secrets.after = ["sops-install-secrets.service"];
        systemd.targets.kdn-secrets.bindsTo = ["sops-install-secrets.service"];
        systemd.services.sops-install-secrets.after = lib.optional (
          config.systemd.targets ? "preservation"
        ) "preservation.target";
        systemd.services.sops-install-secrets.requires = lib.optional (
          config.systemd.targets ? "preservation"
        ) "preservation.target";
      }
      {
        # fix for https://github.com/Mic92/sops-nix/pull/680#issuecomment-2580744439
        # see https://github.com/NixOS/nixpkgs/blob/b33acd9911f90eca3f2b11a0904a4205558aad5b/nixos/lib/systemd-lib.nix#L473-L473
        systemd.services.sops-install-secrets.environment.PATH = let
          path = config.systemd.services.sops-install-secrets.path;
        in
          lib.mkForce "${lib.makeBinPath path}:${lib.makeSearchPathOutput "bin" "sbin" path}";
      }
    ]))
    (kdnConfig.util.ifTypes ["darwin"] (lib.mkMerge [
      # nothing required for now
    ]))
  ]);
}
