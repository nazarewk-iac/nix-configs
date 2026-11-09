# Static, host-independent overlays baked into every pinned pkgs variant.
#
# Each overlay here is a pure function of `lib`/`prev` (no `config`, no host data), so it is safe
# to share ONE evaluated `pkgs` across every host of a system. The host-dependent overlays (age
# `sops` wrapper, hw-gpu multiGPU package, gaming allowUnfreePredicate) stay OUT — they must be
# handled per host (see the pkgs-pinning task's "biggest risk").
{ lib, inputs }:
let
  # `nixos-icons`, recolored by stylix from the theme palette. A pinned host cannot carry stylix's
  # per-host overlay, so the base provides the recolored icon for the ONE default palette
  # (`modules/universal/stylix.pallette.yaml`, darcula-kdn). These are that palette's base05/base0C/
  # base0D (hex) and the RGB components stylix's `baseColorAdd` needs. Keep them in sync if the
  # default palette changes.
  #
  # A device that uses a DIFFERENT theme (a different `stylix.base16Scheme`) yields a different
  # icon and so must NOT pin against this base — give it its own pkgs variant or leave it unpinned.
  iconsColors = {
    scheme = "Darcula by kdn";
    base05 = "a9b7c6";
    base0C = "629755";
    base0D = "9876aa";
    "base0C-rgb-r" = "98";
    "base0C-rgb-g" = "151";
    "base0C-rgb-b" = "85";
    "base0D-rgb-r" = "152";
    "base0D-rgb-g" = "118";
    "base0D-rgb-b" = "170";
  };
  stylixIconsConfig = {
    stylix.enable = true;
    stylix.targets.nixos-icons.enable = true;
    lib.stylix.colors = iconsColors;
  };
in
[
  # `pkgs.nixos-icons` recolored for the default palette (see the `let` above).
  (final: prev:
    (import (inputs.stylix + "/modules/nixos-icons/overlay.nix") {
      pkgs = prev;
      config = stylixIconsConfig;
      lib = lib;
    }).overlay final prev)
  # `pkgs.jsonTemplate`, used by the sops json tTemplate router. Was inline in
  # modules/universal/security/secrets/sops/default.nix.
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
        generate =
          name: value:
          lib.pipe value [
            (json.generate "${name}.wrapped.json")
            builtins.readFile
            (builtins.replaceStrings [ "\"${prefix}" "${suffix}\"" ] [ "" "" ])
            (prev.writeText name)
          ];
      };
  })
  # The pythonMetadataCheck fixes (cython_0) + ceph python metadata. Was inline in
  # modules/universal/default.nix. Both are pure `prev` transformations.
  (final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (
        python-final: python-prev:
        lib.pipe [ "cython_0" ] [
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

  # `pkgs.kdn.kdn-sops-secrets` (the placeholder-resolving command the sops module packs into
  # `kdn.env.packages`). The universal sops module builds this inside its own `nixpkgs.overlays`;
  # a pinned host drops that overlay, so the base must carry the package. Same build, same
  # pattern as modules/universal/security/secrets/sops/default.nix (keep them in sync).
  (final: prev: {
    kdn = (prev.kdn or { }) // {
      kdn-sops-secrets = prev.writers.writePython3Bin "kdn-sops-secrets"
        {
          libraries = with prev.python3Packages; [ fire ];
          flakeIgnore = [ "E203" "E501" ];
        }
        (
          prev.lib.pipe ../../modules/universal/security/secrets/sops/kdn-sops-secrets.py [
            builtins.readFile
            (builtins.replaceStrings
              [ ''pattern: str = ""'' ]
              [ ''pattern = r"<SOPS:(?P<path>[^:]+):(?P<hash>[^:]+):PLACEHOLDER>"'' ]
            )
          ]
        );
    };
  })

  # The `supergfxctl` 5.2.1 downgrade for multi-GPU hosts. nixpkgs' `services.supergfxd` reads
  # `pkgs.supergfxctl` directly (no package option), so it can only be substituted by an overlay.
  # The override is static, so the base carries it; unused by non-multi-GPU hosts.
  (final: prev: {
    supergfxctl = prev.callPackage ../../modules/universal/hw/gpu/supergfxctl.nix { };
  })
]
