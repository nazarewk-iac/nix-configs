# zellij devenv slot.
#
# Installs the zellij package and the .agents/skills/zellij/SKILL.md skill (which mandates:
# never mutate or read pane content in the user's session without explicit per-action consent;
# do own work in a dedicated background session instead).
#
# The Bash permission allowlist below intentionally covers ONLY:
#   - pure discovery/metadata (list-sessions, list-panes, list-tabs, list-clients,
#     current-tab-info) — safe on any session, reveals no pane content
#   - creating/reusing the agent's OWN dedicated background session
#   - one exact, fully static command (no wildcards at all) that dumps only the last line of the
#     agent's OWN pane, via the literal, unexpanded $ZELLIJ_PANE_ID env var reference — Claude
#     Code matches permission rules against the literal command text, not post-expansion, so this
#     can never match a hardcoded/arbitrary pane number or a different command shape. Lets the
#     agent check its own terminal's tail (e.g. an async devenv rebuild status line) without a
#     prompt, since that's the agent's own output, not a read of the user's other panes
# It deliberately does NOT allow-list content reads of other panes (dump-screen -p <other>,
# subscribe, edit-scrollback) or any mutating action (new-pane, new-tab, go-to-tab*,
# focus-pane-id, close-*, kill-session, delete-session, write*, paste, send-keys) — those stay
# behind normal permission prompts so the user is asked every time, matching the skill's consent
# rules.
{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.zellij;

  waitForDevenv = pkgs.writeShellApplication {
    name = "zellij-wait-for-devenv";
    runtimeInputs = [
      pkgs.jq
      pkgs.gawk
    ];
    text = builtins.readFile ./wait-for-devenv.sh;
  };

  waitForDevenvStart = pkgs.writeShellApplication {
    name = "zellij-wait-for-devenv-start";
    runtimeInputs = [
      pkgs.jq
      pkgs.gawk
    ];
    text = builtins.readFile ./wait-for-devenv-start.sh;
  };
in
{
  options.kdn.zellij = {
    enable = lib.mkEnableOption "zellij terminal multiplexer devenv integration";
  };

  config = lib.mkIf cfg.enable {
    devenv = {
      packages = [ pkgs.zellij ];

      claude.code.enable = lib.mkDefault true;

      # Delay a Bash tool call while devenv is mid-rebuild in this same zellij pane (see
      # wait-for-devenv.sh) — instant no-op outside zellij/devenv or once devenv is idle.
      claude.code.hooks.zellij-wait-for-devenv = {
        hookType = "PreToolUse";
        matcher = "Bash";
        command = lib.getExe waitForDevenv;
      };

      # After a file write, briefly poll (up to ~1s) for devenv's watcher to actually start
      # rebuilding (see wait-for-devenv-start.sh) — closes the race where a fast-firing Bash call
      # right after Write/Edit sees a still-stale "devenv ready" and skips the PreToolUse wait
      # above entirely. Always proceeds afterward; never blocks on the rebuild finishing.
      claude.code.hooks.zellij-wait-for-devenv-start = {
        hookType = "PostToolUse";
        matcher = "^(Edit|MultiEdit|Write)$";
        command = lib.getExe waitForDevenvStart;
      };

      # Read-only discovery — safe to always allow, reveals no pane content and cannot mutate
      # session/tab/pane state. Matches without `--session` too (agent's own attached session,
      # $ZELLIJ_SESSION_NAME implicit) and with `--session <name>` targeting any session.
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
        # idempotent: creates the agent's own detached session if missing, no-op otherwise;
        # never touches an existing (e.g. user-attached) session.
        "zellij attach --create-background *"
        # exact, static (no wildcards) — always targets the agent's own pane, e.g. to check an
        # async devenv rebuild's last status line.
        ''zellij action dump-screen -p "$ZELLIJ_PANE_ID" | tail -n 1''
      ];

      files = lib.mkIf (!config.kdn.isSourceRepo) {
        ".claude/skills/zellij/SKILL.md".source = "${inputs.nix-configs}/.agents/skills/zellij/SKILL.md";
      };
    };
  };
}
