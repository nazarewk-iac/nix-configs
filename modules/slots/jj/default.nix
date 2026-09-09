{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.jj;

  jjRepoConfig = (pkgs.formats.toml { }).generate "jj-repo-config.toml" cfg.config;

  jjGuardHook = pkgs.writeShellApplication {
    name = "jj-guard";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./jj-guard.sh;
  };
in
{
  options.kdn.jj = {
    enable = lib.mkEnableOption "jj version control devenv integration";

    alwaysBlockedMessagePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "scratchpad" ];
      description = "Commit message patterns always blocked from pushing to any remote.";
    };

    upstream.remote = lib.mkOption {
      type = lib.types.str;
      default = "kdn";
      description = "Name of the public upstream remote.";
    };
    upstream.url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "URL of the public upstream remote. When set, added automatically on enterShell if missing.";
    };

    fork.enable = lib.mkEnableOption "fork-remote jj config (revset aliases, push/fetch remotes, pre-push protection)";
    fork.remote = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Name of the private fork remote.";
    };
    fork.url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "URL of the private fork remote. When set, added automatically on enterShell if missing.";
    };
    fork.deniedFilePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        File path patterns (case-insensitive) blocked from pushing to non-fork remotes.

        The pre-push hook is one net, not the gate: `jj git push` fires no git hook, and the
        pattern list matches a path or a line, never lock-file structure. `jj fork-audit` is the
        content gate, and `hack/flake-update-complete.sh` is the structural gate.
      '';
    };
    fork.deniedMessagePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Commit message patterns (case-insensitive) blocked from pushing to non-fork remotes.";
    };

    config = lib.mkOption {
      type = (pkgs.formats.toml { }).type;
      default = { };
      description = ''
        Freeform jj repo config (TOML), fed to the generator that gets symlinked to
        `jj config path --repo`. Sibling modules (e.g. fork/default.nix) contribute fragments
        to this attrset instead of generating and symlinking their own config file.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.jj.config."#schema" = "https://docs.jj-vcs.dev/latest/config-schema.json";

    kdn.mcp.extraBackends.jj = {
      command = "${pkgs.kdn.jj-mcp}/bin/jj-mcp";
      description = "jj — Jujutsu version control tools";
    };
    kdn.mcp.programs.git.enable = false;

    devenv = {
      packages = [ pkgs.jujutsu ];

      enterShell = ''
        # symlink jj repo config (merged across all kdn.jj.* modules) to the generated store path
        #
        # `jj config path --repo` returns ONE shared file for the default workspace and every
        # secondary workspace, because the id in the path comes from `.jj/repo/config-id` and a
        # secondary workspace reaches the same store through a `.jj/repo` pointer file. So a
        # `devenv shell` in a secondary workspace would write over the default workspace's config
        # and strip its aliases. Only the default workspace writes the file.
        #
        # The test asks whether this is a SECONDARY workspace, not whether it is the default one.
        # `.jj/repo` is a directory in the default workspace and a small pointer file in a
        # secondary one. A future jj layout change therefore makes this shell write the file, which
        # is today's behaviour, and never makes the default workspace lose its config.
        _jj_config_path="$(jj config path --repo 2>/dev/null)" || true
        _jj_root="$(jj root 2>/dev/null)" || true
        if test -n "$_jj_root" && test -f "$_jj_root/.jj/repo"; then
          echo "kdn.jj: secondary jj workspace — the shared jj repo config stays untouched" >&2
        elif test -n "$_jj_config_path"; then
          ln -sfn ${jjRepoConfig} "$_jj_config_path"
        fi
        unset _jj_config_path _jj_root

        # add a remote (by name/url) via jj itself, no git CLI required, if not already present
        _kdn_jj_ensure_remote() {
          local remote="$1" url="$2"
          if ! jj git remote list | cut -d' ' -f1 | grep -qxF "$remote"; then
            jj git remote add "$remote" "$url"
          fi
        }

        ${lib.optionalString (cfg.upstream.url != null) ''
          _kdn_jj_ensure_remote ${lib.escapeShellArg cfg.upstream.remote} ${lib.escapeShellArg cfg.upstream.url}
        ''}
      '';

      claude.code.enable = true;
      claude.code.hooks.jj-guard = {
        hookType = "PreToolUse";
        matcher = "Bash";
        command = ''cd "$DEVENV_ROOT" && ${lib.getExe jjGuardHook}'';
      };
      # Read-only jj subcommands — safe to always allow, no side effects. Deliberately more
      # specific than a bare "jj file *"/"jj config *" would be: both have mutating subcommands
      # (chmod/track/untrack, set/unset/edit) that must stay gated behind normal permission prompts.
      # Also includes the read-only git exceptions jj-guard.sh already documents as always-allowed
      # at the hook level (kept in sync with ALLOWED_READONLY in ./jj-guard.sh).
      #
      # The `git *` entries below belong to git as a tool, not jj specifically; move them to a
      # dedicated modules/slots/git/ module if/when one is split out.
      claude.code.permissions.rules.Bash.allow = [
        "jj --help"
        "jj help*"
        "jj * --help"
        "jj log *"
        "jj diff *"
        "jj status*"
        "jj show *"
        "jj file show *"
        "jj file list *"
        "jj config get *"
        "jj config list *"
        "jj config path*"
        "jj op log*"
        "jj bookmark list *"
        "git status*"
        "git diff *"
        "git log *"
        "git show *"
        "git check-ignore *"
      ];
      claude.code.agents = lib.mkIf (!config.kdn.isSourceRepo) {
        jj-expert = {
          description = "Deep jj (Jujutsu VCS) troubleshooting: divergent changes, conflicts, graph surgery, revset/fileset/template questions.";
          proactive = true;
          prompt = builtins.readFile "${inputs.nix-configs}/.agents/agents/jj-expert/AGENT.md";
        };
      };

      files = lib.mkIf (!config.kdn.isSourceRepo) {
        ".claude/rules/jujutsu-vcs.md".source = "${inputs.nix-configs}/.agents/rules/jujutsu-vcs.md";
        ".claude/skills/jujutsu-vcs/SKILL.md".source =
          "${inputs.nix-configs}/.agents/skills/jujutsu-vcs/SKILL.md";
      };
    };
  };
}
