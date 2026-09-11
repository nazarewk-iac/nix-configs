# The `jj/fork` slot, as a den aspect. It ports `modules/slots/jj/fork/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It adds the fork-remote half of the jj setup: the push and fetch remotes, about twenty revset
# aliases, five jj aliases, two git hooks and two commands. A repository with one public remote and
# one private fork needs it. A repository with one remote does not.
#
# ## Why it includes `jj`
#
# It writes `kdn.jj.config`, and ./jj.nix declares that option and generates the file. `includes`
# puts both target modules into one evaluation, so this file writes the parent's option directly.
# ./mcp-snoop.nix is the same shape. The `mcp` aspect comes along too, because ./jj.nix includes it.
# den collapses the diamond.
#
# The order also matters, and `includes` gives it: ./jj.nix defines the `_kdn_jj_ensure_remote`
# shell function, and the `enterShell` below calls it. devenv's `enterShell` is a lines option, and
# `lib.mkAfter` puts this half last.
#
# ## The de-personalized port
#
# Two slot defaults carried one person's own data:
#
#  * `alwaysBlockedMessagePatterns` defaulted to a real pattern. A denied pattern is private
#    configuration, so the default here is the empty list and the consumer names its own patterns.
#  * `upstream.remote` defaulted to a personal remote name. ./jj.nix holds that option, and it
#    defaults to `"origin"`.
#
# Both denied-pattern lists already defaulted to the empty list in the slot, so they need no change.
#
# ## A denied pattern reaches the store
#
# Every pattern list becomes a `runtimeEnv` value of a `writeShellApplication`, so it lands in a
# world-readable store path. The slot does the same, and this port keeps the behaviour. A consumer
# that needs a secret pattern must read it at run time instead, from a file that the store does not
# hold.
#
# ## Five files, each a relative path literal
#
# The slot reads three shell files by relative path, and the fork document plus two agent files
# through `"${inputs.nix-configs}/…"`. Each one of the last three is a whole-tree store copy. Every
# read here is a relative path literal, so a derivation depends on one file. See
# ../../../docs/tasks/2026-09/generalization/011-whole-tree-store-copies/definition.md.
#
# ## What the port keeps unchanged
#
# The pre-push hook is one net, not the gate. `jj git push` fires no git hook at all, so it runs no
# check. Only a real `git push` fires the hook, and the `sync-upstream` alias is the one route that
# uses `git push` for the public remote. `jj fork-audit` is the content gate, and
# `hack/flake-update-complete.sh` is the structural gate. The port states the limit and changes
# nothing.
#
# `pre-push.sh` compares the push remote against `PRIVATE_REMOTE` and skips the content checks for
# that one remote only, at `modules/slots/jj/pre-push.sh:86-110`. An earlier review found that test
# inverted. The slot already carries the fix, with 15 tests in `checks/jj-experiments/`, so this port
# reads the corrected script and adds no change of its own.
#
# ## Three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.jj.fork.enable` is gone.
# 3. **No custom module argument.** The target module takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.jj-fork.includes = [ kdn.jj ];

  kdn.jj-fork.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.jj;

      # Join the patterns with a newline, not a space. A consumer script reads them with
      # `mapfile -t`, so a pattern that holds a space stays one element and matches the
      # `fork-direct` revset globs.
      sharedRuntimeEnv = {
        SENSITIVE_FILE_PATTERNS = lib.concatStringsSep "\n" cfg.fork.deniedFilePatterns;
        SENSITIVE_MESSAGE_PATTERNS = lib.concatStringsSep "\n" cfg.fork.deniedMessagePatterns;
      };

      prePushHook = pkgs.writeShellApplication {
        name = "jj-pre-push";
        runtimeInputs = [ pkgs.git ];
        runtimeEnv = sharedRuntimeEnv // {
          PRIVATE_REMOTE = cfg.fork.remote;
          BLOCK_PUSH_MESSAGE_PATTERNS = lib.concatStringsSep "\n" cfg.alwaysBlockedMessagePatterns;
        };
        text = builtins.readFile ../../slots/jj/pre-push.sh;
      };

      checkForkContamination = pkgs.writeShellApplication {
        name = "jj-check-fork-contamination";
        runtimeInputs = [
          pkgs.git
          pkgs.jujutsu
        ];
        runtimeEnv = sharedRuntimeEnv;
        text = builtins.readFile ../../slots/jj/fork/check-fork-contamination.sh;
      };

      # The structural gate for a finished fork flake update. It cannot be a `checks/` derivation: it
      # reads remote-tracking refs and the jj revset engine, so it is impure by nature. It cannot be
      # a git hook either, because `jj git push` fires none. So it ships as a command, and
      # `sync-upstream` prints its verdict before the push prompt.
      flakeUpdateComplete = pkgs.writeShellApplication {
        name = "jj-flake-update-complete";
        runtimeInputs = [
          pkgs.git
          pkgs.jujutsu
          pkgs.jq
        ];
        runtimeEnv.KDN_PUBLIC_REMOTE = cfg.upstream.remote;
        text = builtins.readFile ../../../hack/flake-update-complete.sh;
      };

      forkAudit = pkgs.writeShellApplication {
        name = "jj-fork-audit";
        runtimeInputs = [
          pkgs.git
          pkgs.jujutsu
        ];
        runtimeEnv = sharedRuntimeEnv;
        text = builtins.readFile ../../slots/jj/fork/fork-audit.sh;
      };

      # The same generator call as ./jj.nix, on the same option value. Nix gives one derivation for
      # one input set, so this names the file ./jj.nix already generates. The `enterTest` below reads
      # it.
      jjRepoConfig = (pkgs.formats.toml { }).generate "jj-repo-config.toml" cfg.config;
    in
    {
      # One declaration of `kdn.isSourceRepo`, imported by path. ./jj.nix imports the same file, and
      # the module system drops a repeated import by path. See ../common/.
      imports = [ ../common/source-repo.nix ];

      options.kdn.jj.alwaysBlockedMessagePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Commit message patterns that no push may carry, to any remote.

          The slot defaulted this to one real pattern of one person's own workflow. A denied pattern
          is private configuration, so the default here is empty and the consumer names its own.

          The pre-push hook reads this list. `jj git push` fires no git hook, so it runs no check.
        '';
        example = [ "scratch" ];
      };

      options.kdn.jj.fork.installAgentRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install this aspect's agent instruction files into the consumer repository.

          The files are `.claude/rules/flake-update.fork.md` and
          `.claude/skills/flake-update-fork/SKILL.md`.

          They state the author's own fork update procedure. The default is false, so you get the
          files only when you ask for them. This repository turns the option on explicitly in
          `checks/den-mvp/devenv/default.nix`.

          The option covers instruction files only. The revset aliases, the git hooks and the commands
          stay in place.
        '';
      };

      options.kdn.jj.fork.remote = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Name of the private fork remote.

          The default is the slot's own empty string. An empty value makes the pre-push hook compare
          the push remote against an empty name, which never matches — so every remote gets the
          content checks. A consumer that includes this aspect names its own remote.
        '';
        example = "private";
      };

      options.kdn.jj.fork.url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          URL of the private fork remote. A non-null value makes `enterShell` add the remote when the
          repository does not hold it yet. `null` adds nothing.
        '';
      };

      options.kdn.jj.fork.deniedFilePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          File path patterns, case-insensitive, that no push to a non-fork remote may carry.

          The pre-push hook is one net, not the gate: `jj git push` fires no git hook, and a pattern
          matches a path or a line, never lock-file structure. `jj fork-audit` is the content gate,
          and `hack/flake-update-complete.sh` is the structural gate.

          Every pattern reaches a world-readable store path through `runtimeEnv`.
        '';
        example = [ "internal-hostname" ];
      };

      options.kdn.jj.fork.deniedMessagePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Commit message patterns, case-insensitive, that no push to a non-fork remote may carry.

          The same limit as `deniedFilePatterns` applies: a bare `jj git push` fires no git hook, so
          it runs no check. Only a real `git push` fires the hook, and the `sync-upstream` alias is
          the one route that uses `git push` for the public remote.
        '';
        example = [ "internal-project" ];
      };

      config = {
        kdn.jj.config.git.push = cfg.fork.remote;
        kdn.jj.config.git.fetch = [
          cfg.fork.remote
          cfg.upstream.remote
        ];

        # Every revset alias below comes from the slot, unchanged. The two bookmark names, `main` and
        # `upstream`, stay literal, exactly as the slot spells them.
        kdn.jj.config.revset-aliases = {
          "trunk()" = "main@${cfg.fork.remote}";

          # upstream@<fork-remote> is the last synced point to the public remote. Exclude it, so the
          # revset covers the commits that the public chain does not hold yet.
          fork = lib.concatStringsSep " | " [
            "fork-direct"
            # An ancestor-set difference: ancestors of the fork tip minus ancestors of the upstream
            # anchor. NOT `::(A ~ B)` — A and B are single commits, so that subtraction is a no-op
            # (they are already different commits) and the `::` then walks nearly the whole history.
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

          # tree-merge: the most recent merge commit in the ancestry of @. Every upstream sync is a
          # merge, so this is the anchor that separates local work above from history below.
          tree-merge = "heads(::@ & merges())";

          # upstream-incoming: upstream commits that a fetch brought in, and the local tree does not
          # hold yet. upstream-incoming-tip: the rebase destination, the latest of the incoming set.
          upstream-incoming = "@..main@${cfg.upstream.remote}";
          upstream-incoming-tip = "main@${cfg.upstream.remote}";

          # fork-incoming / fork-incoming-tip: the same pair for the fork remote. Step 0 of the
          # update procedure reads both pairs after a fetch. Both must be empty before the update
          # starts, because every later placement reads a remote-tracking ref.
          fork-incoming = "@..main@${cfg.fork.remote}";
          fork-incoming-tip = "main@${cfg.fork.remote}";

          # to-rebase: every local described change above the tree merge — the set to relocate onto
          # new upstream. Use `roots(to-rebase)` as the rebase source.
          to-rebase = "tree-merge..@ & ~description(\"\")";

          # upstream-safe: the content-clean subset of to-rebase. It uses `~fork-direct`, the
          # sensitive-content predicate, and NOT `~fork` — the `fork` alias tags every descendant of
          # the fork main for topology reasons, so `~fork` drops safe local changes too.
          upstream-safe = "to-rebase & ~fork-direct";

          # pushed*: reachability from a remote bookmark. A change that a remote bookmark reaches is
          # already published there. Use `<change> & ~pushed` to find a purely local change that is
          # still safe to rewrite. Compare with the `immutable()` alias, which also folds in
          # `trunk()`, `tags()` and an untracked remote bookmark.
          pushed = "::remote_bookmarks()";
          pushed-fork = "::remote_bookmarks(remote=\"${cfg.fork.remote}\")";
          pushed-upstream = "::remote_bookmarks(remote=\"${cfg.upstream.remote}\")";

          # fork-leaked: local work above the merge that carries fork-sensitive content. A non-empty
          # result means a change fails an upstream push. The name lets a check need no inline `&`.
          fork-leaked = "to-rebase & fork-direct";

          # merge-frozen: the tree merge is already published or immutable. A non-empty result means
          # you must build a NEW merge instead of a rewrite of the current one. Empty means reuse.
          merge-frozen = "tree-merge & (immutable() | pushed)";

          # upstream-local: local upstream-side commits below the merge that the public remote does
          # not hold yet. These are the pre-merge upstream chain. To pull new upstream in, rebase
          # `roots(upstream-local)` onto `upstream-incoming-tip` — the merge, `to-rebase` and `@`
          # follow as descendants, and the merge keeps its fork parent. Do NOT rebase `tree-merge`
          # directly: that replaces the merge parents and orphans this chain out of the merge
          # ancestry.
          upstream-local = "pushed-upstream..(::tree-merge & ~fork)";
        };

        kdn.jj.config.aliases.fork-audit = [
          "util"
          "exec"
          "--"
          (lib.getExe forkAudit)
        ];
        kdn.jj.config.aliases.update-check = [
          "util"
          "exec"
          "--"
          (lib.getExe flakeUpdateComplete)
        ];
        kdn.jj.config.aliases.fork-help = [
          "util"
          "exec"
          "--"
          "bash"
          "-c"
          # Show the fork document through a pager when the caller is interactive. Prefer $PAGER,
          # fall back to less, fall back to cat. A caller with no TTY always gets plain cat.
          #
          # The path is a relative path literal, so the derivation reads one file. The slot read it
          # through `"''${inputs.nix-configs}/…"`, which copies the whole tree.
          ''
            doc="${../../../docs/jujutsu-vcs.fork.md}"
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
        kdn.jj.config.aliases.sync-remotes = [
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
        kdn.jj.config.aliases.sync-upstream = [
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
            # A warning, never a block: this alias also serves an ordinary push, where the
            # finished-update shape does not apply. Read the verdict, then answer the prompt.
            echo '--- flake update completion check (advisory) ---'
            ${lib.getExe flakeUpdateComplete} || true
            echo '--- end of the completion check ---'
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

        packages = [
          forkAudit
          flakeUpdateComplete
        ];

        # `lib.mkAfter` keeps this block after ./jj.nix's own `enterShell`, which defines the
        # function this line calls.
        enterShell = lib.mkAfter ''
          ${lib.optionalString (cfg.fork.url != null) ''
            _kdn_jj_ensure_remote ${lib.escapeShellArg cfg.fork.remote} ${lib.escapeShellArg cfg.fork.url}
          ''}
        '';

        git-hooks.hooks.jj-check-fork-contamination = {
          enable = true;
          name = "jj-check-fork-contamination";
          description = "Reject fork-specific content staged on a public-side commit";
          entry = lib.getExe checkForkContamination;
          stages = [ "pre-commit" ];
          pass_filenames = false;
          always_run = true;
        };

        git-hooks.hooks.jj-pre-push = {
          enable = true;
          name = "jj-pre-push";
          entry = lib.getExe prePushHook;
          stages = [ "pre-push" ];
          pass_filenames = false;
          always_run = true;
        };

        files = lib.mkIf (cfg.fork.installAgentRules && !config.kdn.isSourceRepo) {
          ".claude/rules/flake-update.fork.md".source = ../../../.agents/rules/flake-update.fork.md;
          ".claude/skills/flake-update-fork/SKILL.md".source =
            ../../../.agents/skills/flake-update-fork/SKILL.md;
        };

        # The aspect's own smoke test. Every assertion stays offline: the build sandbox holds no
        # network, no real `$HOME` and no jj repository. So no assertion runs a repository command.
        enterTest = ''
          echo "• jj-fork: the audit command answers --help" >&2
          jj-fork-audit --help >/dev/null

          echo "• jj-fork: the audit command rejects an invalid --color" >&2
          if jj-fork-audit --color=nonsense >/dev/null 2>&1; then
            echo "jj-fork: an invalid --color must exit non-zero" >&2
            exit 1
          fi

          echo "• jj-fork: the generated repo config holds the fork revset aliases" >&2
          grep -Fq 'fork-direct' ${jjRepoConfig}
          grep -Fq 'upstream-tip' ${jjRepoConfig}
          grep -Fq 'merge-frozen' ${jjRepoConfig}

          echo "• jj-fork: the generated repo config holds the five jj aliases" >&2
          for alias in fork-audit update-check fork-help sync-remotes sync-upstream; do
            grep -Fq "$alias" ${jjRepoConfig}
          done

          echo "• jj-fork: every guard command is executable" >&2
          test -x ${lib.getExe prePushHook}
          test -x ${lib.getExe checkForkContamination}
          test -x ${lib.getExe flakeUpdateComplete}
        '';
      };
    };
}
