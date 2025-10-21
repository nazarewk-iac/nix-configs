{
  lib,
  extraRuntimeDeps ? [ ],
  vendorHash ? null,
  buildGoModule,
  watchexec,
  sops,
  age,
  ...
}:
let
  runtimeDeps = [
    watchexec
    sops
    age
  ]
  ++ extraRuntimeDeps;
in
buildGoModule {
  pname = "kdn-secrets";
  version = "0.0.1";

  src = lib.sourceByRegex ./. [
    "^go\.(mod|sum)$"
    "^[^.]+$"
    ".*\.go$"
  ];

  inherit vendorHash;

  subPackages = [ "." ];

  postPatch = ''
    substituteInPlace main.go \
      --replace-fail '/* EXTRA_PATH_PLACEHOLDER */' '"${lib.makeBinPath runtimeDeps}",'
  '';
}
