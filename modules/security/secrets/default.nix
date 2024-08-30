{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.security.secrets;

  # adds additional information (name) to sops-nix placeholders
  # replaces https://github.com/Mic92/sops-nix/blob/be0eec2d27563590194a9206f551a6f73d52fa34/modules/sops/templates/default.nix#L84-L84
  sopsPlaceholders =
    let
      replacements = {
        "/" = ".";
      };
      escape = builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements);
    in
    builtins.mapAttrs
      (name: _: "<SOPS:${escape name}:${builtins.substring 0 8 (builtins.hashString "sha256" name)}:PLACEHOLDER>")
      config.sops.secrets;
in
{
  options.kdn.security.secrets = {
    enable = lib.mkEnableOption "Nix secrets setup";
    allow = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    allowed = lib.mkOption {
      readOnly = true;
      type = with lib.types; bool;
      default = cfg.allow && cfg.enable;
    };
    sshKeyFiles = lib.mkOption {
      type = with lib.types; listOf path;
      default = [ ];
      apply = paths: lib.pipe paths [
        (builtins.map builtins.readFile paths)
      ];
    };
    age.identities = lib.mkOption {
      type = lib.types.listOf lib.types.submodule {
        options = {
          value = lib.mkOption {
            type = lib.types.str;
          };
          description = lib.mkOption {
            type = lib.types.str;
          };
        };
      };
      default = [ ];
    };
    age.genScripts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      apply = packages: lib.pipe packages [
        (builtins.map lib.getExe)
        (builtins.concatStringsSep "\n")
        (text: pkgs.writeShellApplication {
          inherit text;
          name = "kdn-sops-age-gen-keys";
          derivationArgs.passthru.scripts = packages;
          runtimeInputs = with pkgs; [
            coreutils
            ssh-to-age
          ];
        })
      ];
    };
    files = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }@fargs:
        let
          file = fargs.config;
        in
        {
          options.namePrefix = lib.mkOption {
            type = with lib.types; str;
            default = fargs.name;
          };
          options.keyPrefix = lib.mkOption {
            type = with lib.types; str;
            default = "";
            apply = value: lib.pipe value [
              (lib.strings.removeSuffix "/")
              (v: if v != "" then "${v}/" else v)
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
            default = { };
          };
          options.discovered.keys = lib.mkOption {
            readOnly = true;
            type = with lib.types; listOf str;
            default =
              let
                pathsJson = pkgs.runCommand "converted-kdn-sops-nix-${file.namePrefix}.paths.json"
                  { inherit (file) sopsFile; } ''
                  ${lib.getExe pkgs.gojq} -cM --yaml-input '
                    del(.sops) | [ paths(type == "string" and contains("type:str")) | join("/") ]
                  ' <"$sopsFile" >"$out"
                '';
              in
              lib.pipe pathsJson [
                builtins.readFile
                builtins.fromJSON
                (builtins.filter (lib.strings.hasPrefix file.keyPrefix))
              ];
          };
          options.discovered.entries = lib.mkOption {
            readOnly = true;
            default = lib.pipe file.discovered.keys [
              (builtins.map (path: {
                name = "${file.namePrefix}/${lib.strings.removePrefix file.keyPrefix path}";
                value = file.sops // {
                  sopsFile = file.sopsFile;
                  key = path;
                } // (if file.basePath != null then {
                  path = "${file.basePath}/${path}";
                } else { });
              }))
              builtins.listToAttrs
            ];
          };
        }));
      default = [ ];
    };

    placeholders = lib.mkOption {
      description = ''converts `sops.placeholders` into object structure to iterate more easily over it'';
      readOnly = true;
      type = with lib.types; anything;

      # avoids `error: infinite recursion encountered` by not referencing `config.sops.templates` and re-implementing placeholder
      default = lib.pipe config.sops.secrets [
        builtins.attrNames
        (builtins.map (name: lib.attrsets.setAttrByPath
          (lib.strings.splitString "/" name)
          sopsPlaceholders."${name}"))
        # dumb merge
        (builtins.foldl' lib.attrsets.recursiveUpdate { })
      ];
    };

    secrets = lib.mkOption {
      description = ''converts `sops.secrets` into object structure to iterate more easily over it'';
      readOnly = true;
      type = with lib.types; anything;

      default = lib.pipe config.sops.secrets [
        (lib.attrsets.mapAttrsToList (name: value: lib.attrsets.setAttrByPath
          (lib.strings.splitString "/" name)
          value
        ))
        # dumb merge
        (builtins.foldl' lib.attrsets.recursiveUpdate { })
      ];
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.allow || (config.sops.secrets == { } && config.sops.templates == { });
          message = "`sops.secrets` and `sops.templates` must be empty when `kdn.security.secrets.allow` is `false`";
        }
      ];

      nixpkgs.overlays = [
        (final: prev: {
          jsonTemplate =
            let
              json = final.formats.json { };
              prefix = "<UNWRAP:";
              suffix = ":UNWRAP>";
            in
            {
              inherit (json) type;
              unwrap = txt: "${prefix}${txt}${suffix}";
              /* original https://github.com/NixOS/nixpkgs/blob/25494c1d30252a0a58913be296da382fdcc631eb/pkgs/pkgs-lib/formats.nix#L64-L71
        allows unwrapping of string values into raw types
                */
              generate = name: value: lib.pipe value [
                (json.generate "${name}.wrapped.json")
                builtins.readFile
                (builtins.replaceStrings [ "\"${prefix}" "${suffix}\"" ] [ "" "" ])
                (pkgs.writeText name)
              ];
            };
        })
      ];

      environment.systemPackages = (with pkgs; [
        cfg.age.genScripts
        (pkgs.callPackage ./sops/package.nix { })
        age
        ssh-to-age
        ssh-to-pgp
      ]);

      sops.placeholder = sopsPlaceholders;
      # see https://github.com/Mic92/sops-nix/issues/65
      # note: SSH key gets imported automatically
      sops.gnupg.sshKeyPaths = [ ];
      sops.age.sshKeyPaths = [ ];
      sops.age.keyFile = "/var/lib/sops-nix/key.txt";
      sops.age.generateKey = false;
      kdn.security.secrets.age.genScripts = [
        (pkgs.writeShellApplication {
          name = "kdn-sops-age-gen-keys-ssh";
          runtimeInputs = with pkgs; [
            coreutils
            ssh-to-age
          ];
          text = ''
            if test -e /etc/ssh/ssh_host_ed25519_key; then
              ssh-to-age -i /etc/ssh/ssh_host_ed25519_key -private-key
            fi
          '';
        })
      ];
      system.activationScripts.setupSecrets.deps = [
        "kdnGenerateAgeKeys"
        "etc" # in case secrets get written to /etc
      ];
      system.activationScripts.kdnGenerateAgeKeys.deps = lib.pipe [
        "persist-files"
        "impermanencePersistFiles"
      ] [
        (builtins.filter (key: config.system.activationScripts ? key))
      ];
      system.activationScripts.kdnGenerateAgeKeys.text =
        let
          escapedKeyFile = lib.escapeShellArg config.sops.age.keyFile;
        in
        ''
          mkdir -p $(dirname ${escapedKeyFile})
          printf "Rendering %s\n" ${escapedKeyFile}
          ${lib.getExe cfg.age.genScripts} >${escapedKeyFile}
        '';
    }
    (lib.mkIf cfg.allow {
      sops.templates."placeholder.txt".content = ""; # fills-in `sops.placeholder`
      sops.secrets = lib.pipe cfg.files [
        builtins.attrValues
        (builtins.map (file: file.discovered.entries))
        (builtins.foldl' lib.attrsets.recursiveUpdate { })
      ];
    })
  ]);
}
