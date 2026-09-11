{
  config,
  lib,
  pkgs,
  kdnConfig,
  osConfig ? { },
  darwinConfig ? { },
  ...
}@args:
let
  inherit (kdnConfig) self inputs;
  cfg = config.kdn;

  parentConfig =
    let
      ensure = val: if builtins.isAttrs val then val else { };
    in
    ensure osConfig // ensure darwinConfig;
in
{
  imports = [
    ./_stylix.nix
    ./_options.nix
  ]
  ++ lib.optionals (kdnConfig.moduleType == "home-manager") [
    # NOTE: `./default.nix` needs to be pulled into the home-manager.sharedModules to work!
    ./_hm-bootstrap.nix
    inputs.sops-nix.homeManagerModules.default
    (
      { kdnConfig, ... }:
      {
        imports = kdnConfig.util.loadModules {
          curFile = ./default.nix;
          src = ./.;
          suffixes = [
            "/default.nix"
            "/hm.nix"
          ];
        };
      }
    )
  ]
  ++ lib.optionals (kdnConfig.moduleType == "darwin") [
    inputs.home-manager.darwinModules.default
    inputs.nix-homebrew.darwinModules.nix-homebrew
    inputs.sops-nix.darwinModules.default
    inputs.angrr.darwinModules.angrr
  ]
  ++ lib.optionals (kdnConfig.moduleType == "nixos") [
    ./ascii-workaround.nix
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.nur.modules.nixos.default
    inputs.preservation.nixosModules.preservation
    inputs.sops-nix.nixosModules.sops
    inputs.angrr.nixosModules.angrr
  ]
  ++ kdnConfig.util.loadModules {
    curFile = ./default.nix;
    src = ./.;
    suffixes = [ "/default.nix" ];
  }
  /*
    The personal data folder. `data/README.md` holds the sort rule for each sub-directory.

    Each file is a module. It assigns options that this tree declares, so a module holds no
    personal value of its own. `builtins.filter builtins.pathExists` drops an absent file, so
    an adopter deletes the folder and the tree still evaluates.

    Do NOT scan the folder. `lib.filesystem.listFilesRecursive` on a missing directory raises
    an error that `builtins.tryEval` does not catch (measured 2026-09-11). An explicit list is
    the only safe form, so add one line per new data file.

    A string absolute path is a valid module. nixpkgs `lib/modules.nix` reaches
    `applyModuleArgsIfFunction (toString m) (import m) args` for it.
  */
  ++ builtins.filter builtins.pathExists [
    # `data/universal-deps/` — a file that reads `kdnConfig`.
    "${self}/data/universal-deps/desktop-sway-kanshi.nix"
    "${self}/data/universal-deps/development-nix.nix"
    "${self}/data/universal-deps/stylix.nix"
    # `data/universal-safe/` — a file that reads no `kdnConfig`.
    "${self}/data/universal-safe/hw-edid.nix"
    "${self}/data/universal-safe/locale.nix"
    "${self}/data/universal-safe/programs-photoprism.nix"
    "${self}/data/universal-safe/services-printing.nix"
    "${self}/data/universal-safe/services-samba.nix"
  ];

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.extraSpecialArgs =
        (kdnConfig.output.mkSubmodule { moduleType = "home-manager"; }).specialArgs;
      home-manager.backupFileExtension = "hmbackup";
      home-manager.useGlobalPkgs = false;
      home-manager.useUserPackages = true;

      home-manager.sharedModules = [
        ./default.nix
        {
          config = {
            kdn.enable = lib.mkDefault cfg.enable;
            kdn.hostName = cfg.hostName;
          };
        }
        {
          # note: this is MacOS specific, but is entirely optional everywhere since I'm not using apropos/whatis commands
          programs.man.generateCaches = false;
          home.extraOutputsToInstall = [ "man" ];
        }
      ];
    })
    (kdnConfig.util.ifTypes [ "nixos" "darwin" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            networking.hostName = cfg.hostName;
            nix.registry.nixpkgs.flake = inputs.nixpkgs;
            nix.optimise.automatic = true;
            # A `lib.mkDefault`, so a consumer keeps CppNix or another nix with a plain assignment.
            nix.package = lib.mkDefault (
              let
                latest = pkgs.lixPackageSets.latest.lix;
              in
              # TODO: 2025-12-19: lix 2.94.0 failed tests on darwin
              if pkgs.stdenv.hostPlatform.isDarwin then
                latest.overrideAttrs (prev: {
                  doCheck = false;
                  doInstallCheck = false;
                })
              else
                latest
            );
            nixpkgs.overlays = [ self.overlays.default ];
          }
          (lib.mkIf (!kdnConfig.features.microvm-guest) {
            nix.extraOptions = cfg.nixConfig.nix.extraOptions;
            nix.settings = cfg.nixConfig.nix.settings;
            nixpkgs.config = cfg.nixConfig.nixpkgs.config;
          })
          {
            documentation.man.enable = true;
          }
          (
            /*
              pythonMetadataCheck fixes, see:
              - ceph-common https://github.com/NixOS/nixpkgs/issues/542206
              - fix research https://assistant.kagi.com/share/348c2355-c4cc-4d10-88ca-32b89ca79fec
              - the original cause (introducing the check) https://github.com/NixOS/nixpkgs/pull/532778
            */
            let
              /*
                Do NOT add a package here when its metadata check already passes upstream.
                An `overridePythonAttrs` call changes the derivation hash, so the binary cache
                cannot match it, and every dependent package rebuilds too.

                Measured on 2026-09-09 at nixpkgs d6524aa:
                - upstream python314Packages.scipy: cache.nixos.org returns 200
                - the same package with this override: 404
                `scipy` was in this list, so `brys` had to compile it. That build needs more
                memory than the rosetta-builder guest holds, and the compiler was killed.
              */
              affected = [
                "cython_0"
              ];
            in
            {
              nixpkgs.overlays = [
                (final: prev: {
                  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
                    (
                      python-final: python-prev:
                      lib.pipe affected [
                        (map (name: {
                          inherit name;
                          value = python-prev.${name}.overridePythonAttrs (_: {
                            dontCheckPythonMetadata = true;
                          });
                        }))
                        builtins.listToAttrs
                      ]
                    )
                  ];
                })
                (globalFinal: globalPrev: {
                  ceph = builtins.getAttr "ceph" (
                    globalPrev.ceph.overrideScope (
                      final: prev: {
                        ceph-python-common = prev.ceph-python-common.overridePythonAttrs (_: {
                          dontCheckPythonMetadata = true;
                        });
                      }
                    )
                  );
                })
              ];
            }
          )
        ]
      )
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        # lib.mkDefault is 1000, lib.mkOptionDefault is 1500
        disko.enableConfig = lib.mkDefault false;
        documentation.nixos.enable = true;
        documentation.man.man-db.enable = true;
        documentation.man.cache.enable = true;
        documentation.man.cache.generateAtRuntime = true;
      }
    ))
    (kdnConfig.util.ifTypes [ "darwin" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.desktop.enable = lib.mkDefault true; # enable by default?
          }
          {
            environment.enableAllTerminfo = true;
            networking.localHostName = lib.mkDefault config.kdn.hostName;
            networking.computerName = lib.mkDefault config.kdn.hostName;
          }
          {
            # Homebrew is its own concern, so it carries its own switch.
            # `kdn.homebrew.enable` defaults to `false`, and this line keeps every darwin host of
            # this repository on today's value. An adopter writes a plain `false` to opt out.
            kdn.homebrew.enable = lib.mkDefault true;
          }
          (lib.mkIf cfg.homebrew.enable {
            nix-homebrew.mutableTaps = false;
            homebrew.onActivation.upgrade = true;
            homebrew.onActivation.autoUpdate = false;
            homebrew.onActivation.cleanup = "zap";
            programs.zsh.interactiveShellInit = ''
              export HOMEBREW_READ_ONLY=1
            '';
            programs.fish.interactiveShellInit = ''
              set -gx HOMEBREW_READ_ONLY 1
            '';
          })
          (lib.mkIf cfg.homebrew.enable {
            homebrew.enable = true;

            # see https://github.com/zhaofengli/nix-homebrew/issues/128
            homebrew.taps = lib.pipe config.nix-homebrew.taps [
              (lib.filterAttrs (n: _: !lib.hasPrefix "homebrew/" n))
              builtins.attrNames
              (builtins.map (n: {
                name = n;
                # TODO: might be a better idea to trust specific installed casks and formulaes
                #       can be achieved with either nix-darwin or nix-homebrew options,
                # TODO: verify whether nix-darwin might be properly un-trusting removed entries compared to nix-homebrew?
                trusted = true;
              }))
            ];

            nix-homebrew.enable = true;
            nix-homebrew.enableRosetta = pkgs.stdenv.hostPlatform.isAarch64;

            /*
              The flake-input tap scan, now opt-in.

              It reads every `brew-tap--<owner>--<repo>` input of the flake that owns this tree and
              registers each one as a tap. So a consumer inherits the taps of that flake, including a
              private one. `kdn.homebrew.tapsFromFlakeInputs` defaults to `false`, and each darwin
              host of this repository sets it to `true` in its own file.

              `homebrew.taps` above reads `config.nix-homebrew.taps`, so an off switch empties both.

              `kdn.homebrew.enable` now guards this whole block, so a host drops the tap scan and the
              rest of the Homebrew opinion apart. `modules/den/aspects/homebrew.nix` holds the
              standalone form of the same options.
            */
            nix-homebrew.taps = lib.mkIf cfg.homebrew.tapsFromFlakeInputs (
              let
                prefix = "brew-tap--";
              in
              lib.pipe inputs [
                (lib.attrsets.filterAttrs (name: _: lib.strings.hasPrefix prefix name))
                (lib.attrsets.mapAttrs' (
                  name: src: {
                    name = lib.pipe name [
                      (lib.strings.removePrefix prefix)
                      (builtins.replaceStrings [ "--" ] [ "/" ])
                    ];
                    value = src;
                  }
                ))
              ]
            );
          })
          # FIXES
          {
            home-manager.sharedModules = [
              {
                # TODO: figure tmpfiles alternative for MacOS/systemd-less?
                systemd.user.tmpfiles.rules = lib.mkForce [ ];
              }
            ];
            # fixes home directory being `null` in home-manager
            users.users.root.home = "/var/root";
            users.users.root.uid = 0;
          }
        ]
      )
    ))
  ];
}
