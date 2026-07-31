{
  pkgs,
  ...
}:
let
  kdn-slug = pkgs.writeShellApplication {
    name = "kdn-slug";
    runtimeInputs = with pkgs; [
      argc
      jujutsu
      git
      gnused
      gawk
    ];
    # `eval "$(argc --argc-eval ...)"` injects the argc_* variables at runtime. shellcheck
    # cannot see that, so it flags every read of one as SC2154 ("referenced but not assigned").
    # See packages/llm/zellij-llm/default.nix for the same exclusion.
    excludeShellChecks = [ "SC2154" ];
    text = builtins.readFile ./kdn-slug.sh;
  };
in
kdn-slug.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.pytest =
      pkgs.runCommand "kdn-slug-pytest-check"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (ps: [ ps.pytest ]))
            kdn-slug
            pkgs.jujutsu
            pkgs.git
          ];
        }
        ''
          export HOME="$(mktemp -d)"
          cp ${./kdn_slug_test.py} kdn_slug_test.py
          python3 -m pytest kdn_slug_test.py -v
          touch "$out"
        '';
  };
})
