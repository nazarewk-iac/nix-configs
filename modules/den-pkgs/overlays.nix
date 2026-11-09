# Static, host-independent overlays baked into every pinned pkgs variant.
#
# Each overlay here is a pure function of `lib`/`prev` (no `config`, no host data), so it is safe
# to share ONE evaluated `pkgs` across every host of a system. The host-dependent overlays (age
# `sops` wrapper, hw-gpu multiGPU package, gaming allowUnfreePredicate) stay OUT — they must be
# handled per host (see the pkgs-pinning task's "biggest risk").
{ lib }:
[
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
]
