{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.jj;

  sharedRuntimeEnv = {
    SENSITIVE_FILE_PATTERNS = lib.concatStringsSep " " cfg.fork.deniedFilePatterns;
    SENSITIVE_MESSAGE_PATTERNS = lib.concatStringsSep " " cfg.fork.deniedMessagePatterns;
  };

  prePushHook = pkgs.writeShellApplication {
    name = "jj-pre-push";
    runtimeInputs = [ pkgs.git ];
    runtimeEnv = sharedRuntimeEnv // {
      PRIVATE_REMOTE = cfg.fork.remote;
      BLOCK_PUSH_MESSAGE_PATTERNS = lib.concatStringsSep " " cfg.alwaysBlockedMessagePatterns;
    };
    text = builtins.readFile ../pre-push.sh;
  };

  checkForkContamination = pkgs.writeShellApplication {
    name = "jj-check-fork-contamination";
    runtimeInputs = [
      pkgs.git
      pkgs.jujutsu
    ];
    runtimeEnv = sharedRuntimeEnv;
    text = builtins.readFile ./check-fork-contamination.sh;
  };
in
{
  config = lib.mkIf (cfg.enable && cfg.fork.enable) {
    kdn.jj.config = {
      git = {
        push = cfg.fork.remote;
        fetch = [
          cfg.fork.remote
          cfg.upstream.remote
        ];
      };
      revset-aliases = {
        "trunk()" = "main@${cfg.fork.remote}";
        # upstream@<fork-remote> is the last synced point to the public remote; exclude it
        # so the revset only covers commits not yet on the public chain.
        fork = lib.concatStringsSep " | " [
          "fork-direct"
          # ancestor-set difference: ancestors of the fork tip minus ancestors of the upstream
          # anchor. NOT "::(A ~ B)" — A and B are single commits, so that subtraction is a no-op
          # (they're already different commits) and the `::` then walks nearly the whole history.
          "(::remote_bookmarks(remote=\"${cfg.fork.remote}\")) ~ (::upstream@${cfg.fork.remote})"
          "(remote_bookmarks(remote=\"${cfg.fork.remote}\") ~ upstream@${cfg.fork.remote})::"
        ];
        fork-direct = lib.concatStringsSep " | " (
          lib.concatMap (p: [
            "files(prefix-glob-i:**/*${p}**)"
            "diff_lines(glob-i:*${p}*)"
          ]) cfg.fork.deniedFilePatterns
          ++ map (p: "description(glob-i:*${p}*)") cfg.fork.deniedMessagePatterns
        );
        upstream-chain = "~description(\"\") & ~fork";
        fork-chain = "~description(\"\") & fork";
        upstream-tip = "latest(upstream-chain)";
        fork-tip = "latest(fork-chain)";
      };
      aliases.sync-remotes = [
        "util"
        "exec"
        "--"
        "bash"
        "-xeEuo"
        "pipefail"
        "-c"
        ''
          jj sync-upstream
          fork_tip=$(jj log --no-graph -r 'fork-tip' -T 'change_id.short()')
          echo "Fork tip: $fork_tip"
          echo "Changes to push to ${cfg.fork.remote}:main (since main@${cfg.fork.remote}):"
          jj log -r "main@${cfg.fork.remote}..''${fork_tip}" --stat
          read -rp "Push ${cfg.fork.remote}:main? (y/n)" -n 1
          echo
          if test "$REPLY" == y ; then
            jj bookmark set main -r "$fork_tip"
            jj git push --remote=${cfg.fork.remote} --bookmark=main
          else
            echo 'push cancelled'
            exit 1
          fi
        ''
      ];
      aliases.sync-upstream = [
        "util"
        "exec"
        "--"
        "bash"
        "-xeEuo"
        "pipefail"
        "-c"
        ''
          jj git fetch --remote={${cfg.upstream.remote},${cfg.fork.remote}}
          tip=$(jj log --no-graph -r 'upstream-tip' -T 'change_id.short()')
          echo "Tip: $tip"
          echo "Changes to push to ${cfg.upstream.remote}:main (since main@${cfg.upstream.remote}):"
          jj log -r "main@${cfg.upstream.remote}..''${tip}" --stat
          read -rp "Push ${cfg.upstream.remote}:main? (y/n)" -n 1
          echo
          if test "$REPLY" == y ; then
            jj bookmark set upstream -r "$tip"
            git -C "$(jj root)" push ${cfg.upstream.remote} upstream:main
            jj git push --remote=${cfg.fork.remote} --bookmark=upstream
          else
            echo 'push cancelled'
            exit 1
          fi
        ''
      ];
    };

    devenv = {
      enterShell = lib.mkAfter ''
        ${lib.optionalString (cfg.fork.url != null) ''
          _kdn_jj_ensure_remote ${lib.escapeShellArg cfg.fork.remote} ${lib.escapeShellArg cfg.fork.url}
        ''}
      '';

      git-hooks.hooks.jj-check-fork-contamination = {
        enable = true;
        name = "jj-check-fork-contamination";
        description = "Reject fork-specific content staged on a kdn/upstream-side commit";
        entry = lib.getExe checkForkContamination;
        stages = [ "pre-commit" ];
        pass_filenames = false;
        always_run = true;
      };

      # pre-push hook via devenv git-hooks
      git-hooks.hooks.jj-pre-push = {
        enable = true;
        name = "jj-pre-push";
        entry = lib.getExe prePushHook;
        stages = [ "pre-push" ];
        pass_filenames = false;
        always_run = true;
      };

      files = lib.mkIf (!config.kdn.isSourceRepo) {
        ".claude/rules/flake-update.fork.md".source =
          "${inputs.nix-configs}/.agents/rules/flake-update.fork.md";
        ".claude/skills/flake-update-fork/SKILL.md".source =
          "${inputs.nix-configs}/.agents/skills/flake-update-fork/SKILL.md";
      };
    };
  };
}
