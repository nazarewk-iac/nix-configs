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
      kdn.kdn-slug
    ];
    # `eval "$(argc --argc-eval ...)"` injects the argc_* variables at runtime. shellcheck
    # cannot see that, so it flags every read of one as SC2154 ("referenced but not assigned").
    # See packages/llm/kdn-slug/default.nix for the same exclusion.
    excludeShellChecks = [ "SC2154" ];
    text = builtins.readFile ./zellij-llm.sh;
  };
in
zellij-llm.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    # This spawns a real zellij server behind a private ZELLIJ_SOCKET_DIR (see
    # zellij_llm_test.py's fixture). Verified to work under this host's `nix build`
    # (sandbox = false on this Darwin machine, so it represents what runs here). NOT yet
    # verified inside a real sandboxed Linux CI builder (sandbox = true), where unix-socket
    # creation and network limits could differ. Treat this check's portability to CI as
    # unconfirmed until it runs there.
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
