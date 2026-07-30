{
  pkgs,
  ...
}:
let
  zellij-llm = pkgs.writeShellApplication {
    name = "zellij-llm";
    runtimeInputs = with pkgs; [
      argc
      zellij
      jq
      coreutils
    ];
    # argc_* variables are injected at runtime by `eval "$(argc --argc-eval ...)"` —
    # shellcheck has no way to see that, so it flags every read of one as SC2154
    # ("referenced but not assigned"). See packages/llm/kdn-slug/default.nix for the same
    # exclusion.
    excludeShellChecks = [ "SC2154" ];
    text = builtins.readFile ./zellij-llm.sh;
  };
in
zellij-llm.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    # Spawns a real zellij server behind a private ZELLIJ_SOCKET_DIR (see
    # zellij_llm_test.py's fixture) — verified to work under this host's actual `nix build`
    # execution (sandbox = false on this Darwin machine, so this is representative of what
    # runs here); NOT yet verified inside a real sandboxed Linux CI builder (sandbox = true),
    # where unix-socket creation / networking restrictions could behave differently — treat
    # this check's portability to CI as unconfirmed until it's actually run there.
    tests.pytest =
      pkgs.runCommand "zellij-llm-pytest-check"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (ps: [ ps.pytest ]))
            zellij-llm
            pkgs.zellij
          ];
        }
        ''
          export HOME="$(mktemp -d)"
          cp ${./zellij_llm_test.py} zellij_llm_test.py
          python3 -m pytest zellij_llm_test.py -v
          touch "$out"
        '';
  };
})
