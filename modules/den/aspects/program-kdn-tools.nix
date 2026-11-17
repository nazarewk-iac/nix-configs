# The agent-tooling CLIs and their skills, as a den aspect: `kdn-journal`, `kdn-jj-meta`,
# `kdn-okf`, `okf-agent-memory`, `ai-xf` and `okf-guard`.
#
# The old tree installs the same set in `modules/universal/profile/user/kdn/default.nix`. den has
# no `pkgs.kdn` package set, so each package comes through a plain `callPackage` with a path.
#
# The skill links are the cross-repo part: each tool ships a `SKILL.md` under
# `share/<name>/skill/`, and a harness reads a global skill from `~/.agents/skills`,
# `~/.config/opencode/skills` or `~/.pi/agent/skills`.
{ ... }:
{
  kdn.program-kdn-tools.homeManager =
    { lib, pkgs, ... }:
    let
      kdn-journal = pkgs.callPackage ../../../packages/kdn-journal { };
      kdn-jj-meta = pkgs.callPackage ../../../packages/kdn-jj-meta { };
      kdn-okf = pkgs.callPackage ../../../packages/kdn-okf { };
      okf-agent-memory = pkgs.callPackage ../../../packages/okf-agent-memory { };
      ai-xf = pkgs.callPackage ../../../packages/ai-xf { };
      okf-guard = pkgs.callPackage ../../../packages/okf-guard { };
      okf-rs = pkgs.callPackage ../../../packages/okf-rs { };
      okflint = pkgs.callPackage ../../../packages/okflint { };
      okph = pkgs.callPackage ../../../packages/okph { };
    in
    {
      home.packages = [
        kdn-journal
        kdn-jj-meta
        kdn-okf
        okf-agent-memory
        ai-xf
        okf-guard
        okf-rs
        okflint
        okph
      ];

      home.file = lib.listToAttrs (
        lib.concatMap
          (root: [
            {
              name = "${root}/kdn-journal/SKILL.md";
              value.source = "${kdn-journal}/share/kdn-journal/skill/SKILL.md";
            }
            {
              name = "${root}/kdn-jj-meta/SKILL.md";
              value.source = "${kdn-jj-meta}/share/kdn-jj-meta/skill/SKILL.md";
            }
            {
              name = "${root}/kdn-okf/SKILL.md";
              value.source = "${kdn-okf}/share/kdn-okf/skill/SKILL.md";
            }
            {
              name = "${root}/okf-memory";
              value.source = "${okf-agent-memory}/share/okf-agent-memory/skill";
            }
          ])
          [
            ".agents/skills"
            ".config/opencode/skills"
            ".pi/agent/skills"
          ]
      );
    };
}
