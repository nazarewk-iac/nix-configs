# The `zellij` slot, as a den aspect. It ports `modules/slots/zellij/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs zellij and two helper packages, two Claude Code hooks, a read-only Bash allowlist,
# and one agent skill. The skill holds one rule: an agent never changes and never reads the user's
# own zellij session. The agent runs its own work in a dedicated background session instead.
#
# The allowlist covers three shapes only:
#
#  1. Pure discovery. It reveals no pane content and it changes no state.
#  2. The creation of the agent's **own** detached session. It is idempotent.
#  3. One exact command, with no wildcard, that dumps the last line of the agent's **own** pane.
#     Claude Code matches the literal command text, before the shell expands `$ZELLIJ_PANE_ID`. So
#     this rule can never match a hardcoded pane number or another command shape.
#
# It deliberately holds no content read of another pane (`dump-screen -p <other>`, `subscribe`,
# `edit-scrollback`) and no mutating action (`new-pane`, `new-tab`, `go-to-tab*`, `focus-pane-id`,
# `close-*`, `kill-session`, `delete-session`, `write*`, `paste`, `send-keys`). Each of those stays
# behind a normal permission prompt, so the user answers every time.
#
# ## The two hooks
#
# `zellij-wait-for-devenv` delays a Bash tool call while devenv rebuilds in the same zellij pane.
# It is an instant no-op outside zellij and devenv, and also when devenv is idle.
#
# `zellij-wait-for-devenv-start` polls for up to about one second after a file write, until
# devenv's watcher starts a rebuild. It closes one race: a Bash call that fires directly after a
# write reads a stale "devenv ready" state, and then the hook above skips its wait. This hook always
# continues afterwards. It never waits for the rebuild to finish.
#
# ## Three ports that differ from the slot
#
#  1. **The helper packages come from `pkgs.callPackage`.** The slot reads `pkgs.kdn.kdn-slug` and
#     `pkgs.kdn.zellij-llm`, so it needs this repository's `packages` overlay. A den consumer
#     supplies a plain `pkgs`, so this aspect calls the package directory itself. `zellij-llm` takes
#     `kdn-slug` as a plain argument for exactly this reason.
#  2. **Each repository file is a relative path literal.** The slot writes
#     `"${inputs.nix-configs}/…"`. That is a second whole-tree fetch, and an edit to any unrelated
#     file invalidates it. A relative literal stays inside the tree the evaluation already reads, so
#     it adds no fetch and no second copy. See
#     ../../../docs/tasks/2026-09/generalization/011-whole-tree-store-copies/definition.md.
#  3. **`kdn.isSourceRepo` arrives through an import by path.** See ../common/source-repo.nix.
#
# ## Where the two shell scripts move later
#
# This aspect reads `wait-for-devenv.sh` and `wait-for-devenv-start.sh` from the slot directory. The
# creator's instruction on 2026-09-10 keeps every file in place for now. A duplicate copy drifts in
# silence, and a dangling path fails loudly, so den reads the slot's copy. When the slot tree goes
# away, the two scripts move to `modules/den/aspects/zellij/` and this file becomes a directory. See
# ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
#    An argument such as `inputs` would force the consumer to pass `specialArgs`.
{ ... }:
{
  den.aspects.zellij.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      kdn-slug = pkgs.callPackage ../../../packages/llm/kdn-slug { };
      zellij-llm = pkgs.callPackage ../../../packages/llm/zellij-llm { inherit kdn-slug; };

      waitForDevenv = pkgs.writeShellApplication {
        name = "zellij-wait-for-devenv";
        runtimeInputs = [
          pkgs.jq
          pkgs.gawk
        ];
        text = builtins.readFile ../../slots/zellij/wait-for-devenv.sh;
      };

      waitForDevenvStart = pkgs.writeShellApplication {
        name = "zellij-wait-for-devenv-start";
        runtimeInputs = [
          pkgs.jq
          pkgs.gawk
        ];
        text = builtins.readFile ../../slots/zellij/wait-for-devenv-start.sh;
      };
    in
    {
      imports = [ ../common/source-repo.nix ];

      packages = [
        pkgs.zellij
        kdn-slug
        zellij-llm
      ];

      claude.code.enable = lib.mkDefault true;

      claude.code.hooks.zellij-wait-for-devenv = {
        hookType = "PreToolUse";
        matcher = "Bash";
        command = lib.getExe waitForDevenv;
      };

      claude.code.hooks.zellij-wait-for-devenv-start = {
        hookType = "PostToolUse";
        matcher = "^(Edit|MultiEdit|Write)$";
        command = lib.getExe waitForDevenvStart;
      };

      # Read-only discovery. It reveals no pane content and it changes no session, tab or pane
      # state. Each rule matches with no `--session` (the agent's own attached session) and with an
      # explicit `--session <name>`.
      claude.code.permissions.rules.Bash.allow = [
        "zellij --help"
        "zellij help*"
        "zellij * --help"
        "zellij list-sessions*"
        "zellij action list-panes *"
        "zellij --session * action list-panes *"
        "zellij action list-tabs *"
        "zellij --session * action list-tabs *"
        "zellij action list-clients*"
        "zellij --session * action list-clients*"
        "zellij action current-tab-info*"
        "zellij --session * action current-tab-info*"
        # Idempotent. It creates the agent's own detached session when none exists, and it is a
        # no-op otherwise. It never reaches a session that a user attached.
        "zellij attach --create-background *"
        # Exact and static, with no wildcard. It always names the agent's own pane, for example to
        # read the last status line of an asynchronous devenv rebuild.
        ''zellij action dump-screen -p "$ZELLIJ_PANE_ID" | tail -n 1''
      ];

      # One file, not a whole tree. See rule 2 in the header.
      files = lib.mkIf (!config.kdn.isSourceRepo) {
        ".claude/skills/zellij/SKILL.md".source = ../../../.agents/skills/zellij/SKILL.md;
      };

      # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
      #
      # devenv puts this in `config.enterTest` (`types.lines`, so several aspects merge). It runs
      # under `devenv test` and under `checks.<system>.den-smoke-*`. It never runs on shell entry,
      # and it never runs during a nix-darwin or a NixOS activation.
      #
      # Every assertion stays offline. The check runs inside the build sandbox, which has no
      # network, no real `$HOME` and no zellij server. So no assertion starts a session.
      enterTest = ''
        echo "• zellij: the binary reports a version" >&2
        zellij --version | grep -qE '^zellij [0-9]+\.'

        echo "• zellij: kdn-slug parses its arguments" >&2
        kdn-slug --help >/dev/null

        echo "• zellij: zellij-llm lists its subcommands" >&2
        zellij-llm --help 2>&1 | grep -qE 'spawn'
      '';
    };
}
