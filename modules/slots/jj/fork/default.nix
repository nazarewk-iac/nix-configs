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

        # tree-merge: the most recent merge commit in the ancestry of @. Every upstream sync is
        # a merge, so this is the anchor that separates local work above from history below.
        tree-merge = "heads(::@ & merges())";

        # upstream-incoming: upstream commits fetched but not yet in the local tree.
        # upstream-incoming-tip: the rebase destination (latest of the incoming set).
        upstream-incoming = "@..main@${cfg.upstream.remote}";
        upstream-incoming-tip = "main@${cfg.upstream.remote}";

        # to-rebase: all local described work above the tree merge, i.e. the changes to relocate
        # onto new upstream. Use roots(to-rebase) as the rebase source.
        to-rebase = "tree-merge..@ & ~description(\"\")";

        # upstream-safe: the content-clean subset of to-rebase. It uses ~fork-direct (the
        # sensitive-content predicate), NOT ~fork — the fork alias tags every descendant of the
        # fork main for topology reasons, so ~fork drops safe local changes too.
        upstream-safe = "to-rebase & ~fork-direct";

        # pushed*: reachability from a remote bookmark. A change reachable from a remote bookmark
        # is already published there. Use `<change> & ~pushed` to find purely local changes that
        # are still safe to rewrite. Compare with the immutable() alias, which also folds in
        # trunk(), tags(), and untracked remote bookmarks.
        pushed = "::remote_bookmarks()";
        pushed-fork = "::remote_bookmarks(remote=\"${cfg.fork.remote}\")";
        pushed-upstream = "::remote_bookmarks(remote=\"${cfg.upstream.remote}\")";

        # fork-leaked: local work above the merge that carries fork-sensitive content. A non-empty
        # result means a change would fail an upstream push. Named so the check needs no inline &.
        fork-leaked = "to-rebase & fork-direct";

        # merge-frozen: the tree merge is already published or immutable. A non-empty result means
        # you must build a NEW merge instead of rewriting the current one. Empty means reuse it.
        merge-frozen = "tree-merge & (immutable() | pushed)";

        # upstream-local: local upstream-side commits below the merge, not yet on the public
        # remote. These are the pre-merge upstream chain. To pull new upstream in, rebase
        # roots(upstream-local) onto upstream-incoming-tip — the merge, to-rebase, and @ follow as
        # descendants, and the merge keeps its fork parent. Do NOT rebase tree-merge directly:
        # that replaces the merge parents and orphans this chain out of the merge ancestry.
        upstream-local = "pushed-upstream..(::tree-merge & ~fork)";
      };
      aliases.fork-help = [
        "util"
        "exec"
        "--"
        "bash"
        "-c"
        # Show the fork doc through a pager when interactive. Prefer $PAGER, fall back to less,
        # fall back to cat. A non-interactive caller (no TTY) always gets plain cat.
        ''
          doc="${inputs.nix-configs}/docs/jujutsu-vcs.fork.md"
          if [ -t 1 ]; then
            pager="''${PAGER:-}"
            if [ -z "$pager" ]; then
              if command -v less >/dev/null 2>&1; then pager="less -R"; else pager="cat"; fi
            fi
            exec $pager "$doc"
          fi
          exec cat "$doc"
        ''
      ];
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
