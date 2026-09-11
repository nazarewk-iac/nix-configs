# The `security/secrets/sops` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns a sops YAML file into a set of `sops.secrets` entries, with no entry written by hand.
# `kdn.security.secrets.sops.files.<name>` names one file, and the aspect reads the file's metadata
# to discover every key inside it. Three helpers come with that:
#
# 1. **`placeholders`** and **`secrets`** re-shape `sops.placeholder` and `sops.secrets` from a flat
#    `a/b/c` name into a nested attribute set, so a template iterates over it.
# 2. **`jsonTemplate`** is a `pkgs.formats.json` variant with an `unwrap` function. It puts a raw
#    JSON value where a plain generator would put a quoted string.
# 3. **`kdn-sops-secrets`** is a small Python command that resolves the placeholder pattern at run
#    time.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old default follows
#    `kdn.security.secrets.enable`, and den has no such flag.
# 2. **`kdn.env.packages` goes.** Each target writes `environment.systemPackages`, through
#    ../common/filter-packages.nix. Design B.
# 3. **The aspect imports the sops-nix module itself.** The old tree imports it for every host.
#    Precedent: ./disks.nix:206-207.
# 4. **`kdn-sops-secrets` leaves the overlay.** The old module builds it inside `nixpkgs.overlays`
#    as `pkgs.kdn.kdn-sops-secrets`, and den has no `kdn` package set. This aspect builds the
#    command directly with `pkgs.writers.writePython3Bin`. The overlay stays for `jsonTemplate`
#    alone, because the router module of the old tree reads that name from `pkgs`.
# 5. **`kdnConfig.util.hasSops` goes.** This aspect always imports sops-nix, so `config.sops` is
#    always there. `or { }` covers the class that carries no sops module.
# 6. **The metadata parser comes from ../../../lib/sops.** That file takes `lib` alone and reads no
#    option, so an aspect may import it.
#
# ## The absent-path trap
#
# `builtins.readFile` on an absent path stops the whole evaluation, and `builtins.tryEval` does not
# catch it. `hasDefaultFile` tests the path with `builtins.pathExists` first, and every reader of
# `defaultFile` must read that flag before the path. `discovered.keys` reads a `sopsFile` that a
# consumer names, so a consumer that names an absent file gets the same abort. That matches the old
# module.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The `enable` keys inside
#    `files.<name>` do not exist, and every other option is data.
# 3. **No custom module argument.** Each target module takes `config`, `lib` and `pkgs` only.
#    `inputs` comes from this file's own scope, because the check harness passes `pkgs` alone to a
#    target.
{ kdn, inputs, ... }:
let
  # `lib` arrives as a target-module argument, never as an aspect-file argument. So every helper
  # that needs it takes it. ./toolset.nix:65 uses the same shape.
  sopsLibFor = lib: import ../../../lib/sops { inherit lib; };

  # The placeholder text sops-nix substitutes at activation time. It adds the secret name to the
  # sops-nix form, so a template failure names the secret that caused it. It replaces
  # https://github.com/Mic92/sops-nix/blob/be0eec2d27563590194a9206f551a6f73d52fa34/modules/sops/templates/default.nix#L84-L84
  sopsPlaceholderPattern =
    {
      name ? "",
      path ? "",
      hash ? if name != "" then builtins.substring 0 8 (builtins.hashString "sha256" name) else "",
      infix ? "${path}:${hash}",
    }:
    "<SOPS:${infix}:PLACEHOLDER>";

  placeholdersOf =
    config:
    builtins.mapAttrs (
      name: secretCfg:
      sopsPlaceholderPattern {
        inherit name;
        inherit (secretCfg) path;
      }
    ) (config.sops.secrets or { });

  declaration =
    { config, lib, ... }:
    let
      cfg = config.kdn.security.secrets.sops;
      safeSopsSecrets = config.sops.secrets or { };
      sopsPlaceholders = placeholdersOf config;
    in
    {
      options.kdn.security.secrets.sops.defaultFile = lib.mkOption {
        type = with lib.types; nullOr path;
        default = null;
        example = "/etc/nixos/my.unattended.sops.yaml";
        description = ''
          Sops file that the default profiles read. `null` means the tree holds none.

          The engine holds no path of its own, so a consumer that names no file gets no secret and
          the tree still evaluates.
        '';
      };

      options.kdn.security.secrets.sops.hasDefaultFile = lib.mkOption {
        readOnly = true;
        type = with lib.types; bool;
        default = cfg.defaultFile != null && builtins.pathExists cfg.defaultFile;
        description = ''
          True when `defaultFile` names a path that exists.

          Read this flag before you read the path. `builtins.readFile` on an absent path stops the
          whole evaluation, and `builtins.tryEval` does not catch that.
        '';
      };

      options.kdn.security.secrets.sops.files = lib.mkOption {
        default = { };
        description = ''
          One entry per sops file. The aspect reads each file's metadata, lists every key inside it,
          and writes one `sops.secrets` entry per key.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@fargs:
            let
              fileCfg = fargs.config;
            in
            {
              options.namePrefix = lib.mkOption {
                type = with lib.types; str;
                default = fargs.name;
                description = "What every generated secret name starts with.";
              };
              options.keyPrefix = lib.mkOption {
                type = with lib.types; str;
                default = "";
                description = "Take only the keys under this path, and cut the prefix off the name.";
                apply =
                  value:
                  lib.pipe value [
                    (lib.strings.removeSuffix "/")
                    (v: if v != "" then "${v}/" else v)
                  ];
              };
              options.sopsFile = lib.mkOption {
                type = with lib.types; path;
                description = "The sops YAML file this entry reads.";
              };
              options.basePath = lib.mkOption {
                type = with lib.types; nullOr path;
                default = null;
                description = "Write every secret under this directory. `null` keeps the sops-nix default.";
              };
              options.sops = lib.mkOption {
                type = with lib.types; attrsOf anything;
                default = { };
                description = "Extra sops-nix settings for every secret of this file.";
              };
              options.overrides = lib.mkOption {
                type = with lib.types; listOf anything;
                default = [ ];
                description = "Functions `name: old: attrs` that change one generated entry.";
              };
              options.filters = lib.mkOption {
                type = with lib.types; listOf anything;
                default = [ ];
                description = "Predicates on the key name. A key passes when every predicate holds.";
              };
              options.discovered.keys = lib.mkOption {
                readOnly = true;
                type = with lib.types; listOf str;
                default = lib.pipe fileCfg.sopsFile [
                  (sopsLibFor lib).parseSopsYAMLMetadata
                  (map (e: builtins.concatStringsSep "/" e.path))
                  (builtins.filter (lib.strings.hasPrefix fileCfg.keyPrefix))
                  (map (lib.strings.removePrefix fileCfg.keyPrefix))
                  (builtins.filter (key: builtins.all (f: f key) fileCfg.filters))
                ];
                description = "Every key this entry takes from the file.";
              };
              options.discovered.entries = lib.mkOption {
                readOnly = true;
                default = lib.pipe fileCfg.discovered.keys [
                  (map (
                    key:
                    let
                      path = "${fileCfg.keyPrefix}${key}";
                    in
                    {
                      name = "${fileCfg.namePrefix}/${key}";
                      value =
                        fileCfg.sops
                        // {
                          sopsFile = fileCfg.sopsFile;
                          key = path;
                        }
                        // (
                          if fileCfg.basePath != null then
                            {
                              path = "${fileCfg.basePath}/${path}";
                            }
                          else
                            { }
                        );
                    }
                  ))
                  builtins.listToAttrs
                  (builtins.mapAttrs (
                    name: secretCfg:
                    lib.lists.foldl' (old: override: old // override name old) secretCfg fileCfg.overrides
                  ))
                ];
                description = "The `sops.secrets` entries this file produces.";
              };
            }
          )
        );
      };

      options.kdn.security.secrets.sops.placeholders = lib.mkOption {
        description = "Turns `sops.placeholder` into a nested set, so a template iterates over it.";
        readOnly = true;
        type = with lib.types; anything;

        # It re-implements the placeholder text instead of a read of `config.sops.templates`. A read
        # there makes an infinite recursion.
        default = lib.pipe safeSopsSecrets [
          builtins.attrNames
          (map (
            name: lib.attrsets.setAttrByPath (lib.strings.splitString "/" name) sopsPlaceholders."${name}"
          ))
          # dumb merge
          (builtins.foldl' lib.attrsets.recursiveUpdate { })
        ];
      };

      options.kdn.security.secrets.sops.secrets = lib.mkOption {
        description = "Turns `sops.secrets` into a nested set, so a template iterates over it.";
        readOnly = true;
        type = with lib.types; anything;

        default = lib.pipe safeSopsSecrets [
          (lib.attrsets.mapAttrsToList (
            name: value: lib.attrsets.setAttrByPath (lib.strings.splitString "/" name) value
          ))
          # dumb merge
          (builtins.foldl' lib.attrsets.recursiveUpdate { })
        ];
      };
    };

  # The Python command. The old module builds it inside the overlay; this builds it directly.
  mkSopsSecretsCommand =
    { lib, pkgs }:
    let
      pattern = sopsPlaceholderPattern {
        path = "(?P<path>[^:]+)";
        hash = "(?P<hash>[^:]+)";
      };
      r.pattern = ''pattern: str = ""'';
      replacements = {
        "${r.pattern}" = ''pattern = r"${pattern}"'';
      };
    in
    pkgs.writers.writePython3Bin "kdn-sops-secrets"
      {
        libraries = with pkgs.python3Packages; [
          fire
        ];
      }
      (
        lib.pipe ./security-secrets-sops/kdn-sops-secrets.py [
          builtins.readFile
          (builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements))
        ]
      );

  packagesOf =
    { lib, pkgs }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    filterPackages [
      pkgs.sops
      (mkSopsSecretsCommand { inherit lib pkgs; })
    ];

  # `jsonTemplate` keeps its overlay. The old router module reads the name from `pkgs`.
  jsonTemplateOverlayFor = lib: final: prev: {
    jsonTemplate =
      let
        json = final.formats.json { };
        prefix = "<UNWRAP:";
        suffix = ":UNWRAP>";
      in
      {
        inherit (json) type;
        unwrap = txt: "${prefix}${txt}${suffix}";
        # It follows
        # https://github.com/NixOS/nixpkgs/blob/25494c1d30252a0a58913be296da382fdcc631eb/pkgs/pkgs-lib/formats.nix#L64-L71
        # and it unwraps a string value into a raw JSON type.
        generate =
          name: value:
          lib.pipe value [
            (json.generate "${name}.wrapped.json")
            builtins.readFile
            (builtins.replaceStrings [ "\"${prefix}" "${suffix}\"" ] [ "" "" ])
            (prev.writeText name)
          ];
      };
  };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.security.secrets.sops;
    in
    {
      imports = [
        declaration
        inputs.sops-nix.nixosModules.sops
      ];

      environment.systemPackages = packagesOf { inherit lib pkgs; };

      sops.placeholder = placeholdersOf config;

      nixpkgs.overlays = [ (jsonTemplateOverlayFor lib) ];

      sops.templates = lib.mkIf config.kdn.security.secrets.allow {
        # It fills `sops.placeholder` in.
        "placeholder.txt".content = "";
      };
      sops.secrets = lib.mkIf config.kdn.security.secrets.allow (
        lib.pipe cfg.files [
          builtins.attrValues
          (map (fileCfg: fileCfg.discovered.entries))
          lib.mkMerge
        ]
      );

      assertions = [
        {
          assertion = config.services.userborn.enable || config.services.sysusers.enable;
          message = "either `services.{userborn,sysusers}.enable` must be enabled for `sops-nix` to integrate into the system properly";
        }
      ];

      systemd.targets.kdn-secrets.after = [ "sops-install-secrets.service" ];
      systemd.targets.kdn-secrets.bindsTo = [ "sops-install-secrets.service" ];
      systemd.services.sops-install-secrets.after = lib.optional (
        config.systemd.targets ? "preservation"
      ) "preservation.target";
      systemd.services.sops-install-secrets.requires = lib.optional (
        config.systemd.targets ? "preservation"
      ) "preservation.target";

      # A fix for https://github.com/Mic92/sops-nix/pull/680#issuecomment-2580744439 . See
      # https://github.com/NixOS/nixpkgs/blob/b33acd9911f90eca3f2b11a0904a4205558aad5b/nixos/lib/systemd-lib.nix#L473-L473
      systemd.services.sops-install-secrets.environment.PATH =
        let
          path = config.systemd.services.sops-install-secrets.path;
        in
        lib.mkForce "${lib.makeBinPath path}:${lib.makeSearchPathOutput "bin" "sbin" path}";
    };

  darwinTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.security.secrets.sops;
    in
    {
      imports = [
        declaration
        inputs.sops-nix.darwinModules.default
      ];

      environment.systemPackages = packagesOf { inherit lib pkgs; };

      sops.placeholder = placeholdersOf config;

      nixpkgs.overlays = [ (jsonTemplateOverlayFor lib) ];

      sops.templates = lib.mkIf config.kdn.security.secrets.allow {
        "placeholder.txt".content = "";
      };
      sops.secrets = lib.mkIf config.kdn.security.secrets.allow (
        lib.pipe cfg.files [
          builtins.attrValues
          (map (fileCfg: fileCfg.discovered.entries))
          lib.mkMerge
        ]
      );
    };
in
{
  kdn.security-secrets-sops.includes = [ kdn.secrets ];

  kdn.security-secrets-sops.nixos = nixosTarget;
  kdn.security-secrets-sops.darwin = darwinTarget;
}
