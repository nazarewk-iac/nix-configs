# Drop a package that cannot build, and warn about it. A plain function, not a module.
#
# ## Where it comes from
#
# `modules/universal/env/default.nix:12-52` runs this pipeline as the `apply` of
# `kdn.env.packages`. den ships no `kdn.env.*` option: a den target names its class, so it writes
# the native option (`environment.systemPackages`, `home.packages` or `packages`) directly. An
# `apply` belongs to one option, so the pipeline needs a new home.
#
# ## How an aspect calls it
#
#     { config, lib, pkgs, ... }:
#     let
#       filterPackages = import ../common/filter-packages.nix { inherit lib; };
#     in
#     {
#       environment.systemPackages = filterPackages [ pkgs.one pkgs.two ];
#     }
#
# The call is per list, so each aspect opts in. No option, no class question, and no module system.
#
# ## What it drops
#
# It drops a package that is broken, unsupported or unavailable, and a package whose `outPath`
# fails to evaluate. It warns once per group and names every dropped package.
#
# ## No caller yet
#
# Batch 1 ports no aspect that ships a package, so this file has no caller today. It lands now
# because it is the whole replacement for the `apply` pipeline, and a later batch needs it ready.
{ lib }:
let
  warnAndFilter =
    { predicate, mkMessage }:
    packages:
    let
      parts = lib.partition predicate packages;
      # parts.right = matched the predicate → warn and discard
      # parts.wrong = did not match         → keep
    in
    if parts.right == [ ] then parts.wrong else lib.warn (mkMessage parts.right) parts.wrong;

  listRepr = lib.flip lib.pipe [
    (map lib.getName)
    (lib.lists.sort (p: q: p < q))
    (lib.strings.concatStringsSep ", ")
  ];
in
lib.flip lib.pipe [
  (warnAndFilter {
    predicate = p: p.meta.broken or false;
    mkMessage = packages: "Excluding broken (meta.broken = true) packages: ${listRepr packages}.";
  })
  (warnAndFilter {
    predicate = p: p.meta.unsupported or false;
    mkMessage =
      packages: "Excluding unsupported (meta.unsupported = true) packages: ${listRepr packages}.";
  })
  (warnAndFilter {
    predicate = p: !(p.meta.available or true);
    mkMessage =
      packages: "Excluding unavailable (meta.available = false) packages: ${listRepr packages}";
  })
  (warnAndFilter {
    predicate = p: !(builtins.tryEval p.outPath).success;
    mkMessage =
      packages: "Excluding packages that fail to evaluate (broken dependencies?): ${listRepr packages}";
  })
]
