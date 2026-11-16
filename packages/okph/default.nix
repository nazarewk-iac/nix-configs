# `okph`: a git-native graph and impact-analysis tool for OKF bundles. It answers "what links to
# this concept, and what does a branch touch?" with `deps`, `dependents` and `affected --git`.
#
# Not in nixpkgs. The tool is pre-1.0, so the version is pinned. The repo has no
# `package-lock.json`; it uses pnpm, so the build goes through `fetchPnpmDeps` and the pnpm
# config hook, and the install carries the built `dist` plus the production `node_modules`.
#
# `pnpm_10` is deliberate. The top-level `fetchPnpmDeps` defaults to pnpm 11 or newer, and with
# that pnpm the config hook tries to reach the registry instead of the offline store. The
# `pnpm_10` fetcher emits a deprecation warning and works.
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  pnpm_10,
}:
let
  pname = "okph";
  version = "0.9.0";
in
stdenv.mkDerivation rec {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "Fcmam5";
    repo = "okph";
    rev = "v${version}";
    hash = "sha256-habJ9eRwjykpmy0r51Q3NDUzQA9Sm6wjPyI931IoC6c=";
  };

  pnpmDeps = pnpm_10.fetchDeps {
    inherit pname version src;
    fetcherVersion = 3;
    hash = "sha256-w0a1NZBaMxGtjzaYhwMwAOh55J4v71gAjwfcJL1SQYk=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10.configHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/okph" "$out/bin"
    pnpm prune --prod
    cp -r dist node_modules package.json "$out/lib/okph/"
    substituteInPlace "$out/lib/okph/dist/bin/okph.mjs" \
      --replace-fail '#!/usr/bin/env node' '#!${nodejs}/bin/node'
    ln -s "$out/lib/okph/dist/bin/okph.mjs" "$out/bin/okph"
    runHook postInstall
  '';

  meta = {
    description = "Git-native graph and impact analysis for OKF knowledge bases";
    homepage = "https://github.com/Fcmam5/okph";
    license = lib.licenses.mit;
    mainProgram = "okph";
  };
}
