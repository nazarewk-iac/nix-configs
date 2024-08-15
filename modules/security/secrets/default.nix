{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.security.secrets;
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
          options.path = lib.mkOption {
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
                    del(.sops) | [ paths(([type] - ["string"]) == []) | join("/") ]
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
                } // (if file.path != null then {
                  path = "${file.path}/${path}";
                } else { });
              }))
              builtins.listToAttrs
            ];
          };
        }));
      default = [ ];
    };

    placeholders = lib.mkOption {
      description = ''converts `sops.placeholders` into object structure to iterate'';
      readOnly = true;
      type = with lib.types; anything;

      # avoids `error: infinite recursion encountered` by not referencing `config.sops.templates` and re-implementing placeholder
      default = lib.pipe config.sops.secrets [
        builtins.attrNames
        (builtins.map (name: lib.attrsets.setAttrByPath
          (lib.strings.splitString "/" name)
          # reimplements https://github.com/Mic92/sops-nix/blob/be0eec2d27563590194a9206f551a6f73d52fa34/modules/sops/templates/default.nix#L84-L84
          "<SOPS:${builtins.hashString "sha256" name}:PLACEHOLDER>"))
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

      environment.systemPackages = (with pkgs; [
        cfg.age.genScripts
        (pkgs.callPackage ./sops/package.nix { })
        age
        ssh-to-age
        ssh-to-pgp
      ]);

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
        "etc" # in case secrets get written to
      ]
      ++ lib.optional (config.environment.persistence != { }) "persist-files" # run after impermanence kicks in
      ;
      system.activationScripts.kdnGenerateAgeKeys =
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
