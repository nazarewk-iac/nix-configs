# Parameterized jj-experiments pytest builder.
#
# extraArgs are baked into the derivation with lib.escapeShellArgs, so the
# derivation hash tracks them: a given arg set caches, and a new one rebuilds.
# extraArgs = [ ] runs the whole suite (the CI gate). A subset passes pytest
# flags, e.g. extraArgs = [ "-k" "placement" ].
#
# The build stays fully sandboxed: HOME is a fresh temp dir, only the declared
# inputs run, and the tests use the isolated jj/git env from conftest.py.
{
  pkgs,
  lib,
  suite, # the suite source (a store path or fileset.toSource result)
  toml, # the rendered fork slot config, exported as JJ_FORK_CONFIG_TOML
  extraArgs ? [ ],
}:
pkgs.runCommand "jj-experiments-pytest-check"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.pytest ]))
      pkgs.jujutsu
      pkgs.git
    ];
    JJ_FORK_CONFIG_TOML = toml;
  }
  ''
    export HOME="$(mktemp -d)"
    cp -r ${suite}/. ./suite
    chmod -R u+w ./suite
    cd ./suite
    python3 -m pytest -v ${lib.escapeShellArgs extraArgs}
    touch "$out"
  ''
