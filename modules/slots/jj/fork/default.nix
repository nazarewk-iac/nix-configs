{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.jj;

  prePushHook = pkgs.writeShellApplication {
    name = "jj-pre-push";
    runtimeInputs = [ pkgs.git ];
    runtimeEnv = {
      PRIVATE_REMOTE = cfg.fork.remote;
      SENSITIVE_FILE_PATTERNS = lib.concatStringsSep " " cfg.fork.deniedFilePatterns;
      SENSITIVE_MESSAGE_PATTERNS = lib.concatStringsSep " " cfg.fork.deniedMessagePatterns;
      BLOCK_PUSH_MESSAGE_PATTERNS = lib.concatStringsSep " " cfg.alwaysBlockedMessagePatterns;
    };
    text = builtins.readFile ../pre-push.sh;
  };

  forkRepoConfig = (pkgs.formats.toml { }).generate "jj-fork-config.toml" {
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
        "::(remote_bookmarks(remote=\"${cfg.fork.remote}\") ~ upstream@${cfg.fork.remote})"
        "(remote_bookmarks(remote=\"${cfg.fork.remote}\") ~ upstream@${cfg.fork.remote})::"
      ];
      fork-direct = lib.concatStringsSep " | " (
        lib.concatMap (p: [
          "files(prefix-glob-i:**/*${p}**)"
          "diff_lines(glob-i:*${p}*)"
        ]) cfg.fork.deniedFilePatterns
        ++ map (p: "description(glob-i:*${p}*)") cfg.fork.deniedMessagePatterns
      );
      upstream-candidates = "~description(\"\") & ~fork";
      fork-candidates = "~description(\"\") & fork";
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
        fork_candidate=$(jj log --no-graph -r 'latest(fork-candidates)' -T 'change_id.short()')
        echo "Fork candidate: $fork_candidate"
        echo "Changes to push to ${cfg.fork.remote}:main (since main@${cfg.fork.remote}):"
        jj log -r "main@${cfg.fork.remote}..''${fork_candidate}" --stat
        read -rp "Push ${cfg.fork.remote}:main? (y/n)" -n 1
        echo
        if test "$REPLY" == y ; then
          jj bookmark set main -r "$fork_candidate"
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
        candidate=$(jj log --no-graph -r 'latest(upstream-candidates)' -T 'change_id.short()')
        echo "Candidate: $candidate"
        echo "Changes to push to ${cfg.upstream.remote}:main (since main@${cfg.upstream.remote}):"
        jj log -r "main@${cfg.upstream.remote}..''${candidate}" --stat
        read -rp "Push ${cfg.upstream.remote}:main? (y/n)" -n 1
        echo
        if test "$REPLY" == y ; then
          jj bookmark set upstream -r "$candidate"
          git -C "$(jj root)" push ${cfg.upstream.remote} upstream:main
          jj git push --remote=${cfg.fork.remote} --bookmark=upstream
        else
          echo 'push cancelled'
          exit 1
        fi
      ''
    ];
  };
in
{
  config = lib.mkIf (cfg.enable && cfg.fork.enable) {
    enterShell = lib.mkAfter ''
      # merge fork config on top of base jj repo config
      _jj_config_path="$(jj config path --repo 2>/dev/null)" || true
      if test -n "$_jj_config_path"; then
        ln -sfn ${forkRepoConfig} "$_jj_config_path"
      fi
      unset _jj_config_path

      ${lib.optionalString (cfg.fork.url != null) ''
        # add fork remote if missing
        if ! git remote get-url ${lib.escapeShellArg cfg.fork.remote} &>/dev/null; then
          git remote add ${lib.escapeShellArg cfg.fork.remote} ${lib.escapeShellArg cfg.fork.url}
        fi
      ''}
    '';

    # pre-push hook via devenv git-hooks
    git-hooks.hooks.jj-pre-push = {
      enable = true;
      name = "jj-pre-push";
      entry = lib.getExe prePushHook;
      stages = [ "pre-push" ];
      pass_filenames = false;
      always_run = true;
    };

    files = lib.mkMerge [
      { ".claude/rules/flake-update.fork.md".source = ../../../../docs/flake-update.fork.md; }
      (lib.mkIf (!config.kdn.isSourceRepo) {
        ".claude/skills/flake-update-fork/SKILL.md".source = ./SKILL.md;
      })
    ];
  };
}
