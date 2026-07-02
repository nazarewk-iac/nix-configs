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
    text = builtins.readFile ./pre-push.sh;
  };

  jjRepoConfig = (pkgs.formats.toml { }).generate "jj-repo-config.toml" (
    {
      "#schema" = "https://docs.jj-vcs.dev/latest/config-schema.json";
    }
    // lib.optionalAttrs cfg.fork.enable {
      git = {
        push = cfg.fork.remote;
        fetch = [
          cfg.fork.remote
          "kdn"
        ];
      };
      revset-aliases = {
        "trunk()" = "main@${cfg.fork.remote}";
        # upstream@<fork-remote> is the last synced point to kdn; exclude it so we only
        # see pton-side commits not yet on the public chain.
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
      aliases.sync-upstream = [
        "util"
        "exec"
        "--"
        "bash"
        "-xeEuo"
        "pipefail"
        "-c"
        ''
          jj git fetch --remote={kdn,${cfg.fork.remote}}
          candidate=$(jj log --no-graph -r 'latest(upstream-candidates)' -T 'change_id.short()')
          echo "Candidate: $candidate"
          echo "Changes to push to kdn:main (since main@kdn):"
          jj log -r "main@kdn..''${candidate}" --stat
          read -rp "Push kdn:main? (y/n)" -n 1
          echo
          if test "$REPLY" == y ; then
            jj bookmark set upstream -r "$candidate"
            git -C "$(jj root)" push kdn upstream:main
            jj git push --remote=${cfg.fork.remote} --bookmark=upstream
          else
            echo 'push cancelled'
            exit 1
          fi
        ''
      ];
    }
  );
in
{
  options.kdn.jj = {
    enable = lib.mkEnableOption "jj version control devenv integration";

    alwaysBlockedMessagePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "scratchpad" ];
      description = "Commit message patterns always blocked from pushing to any remote.";
    };

    fork.enable = lib.mkEnableOption "fork-remote jj config (revset aliases, push/fetch remotes, pre-push protection)";
    fork.remote = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Name of the private fork remote.";
    };
    fork.deniedFilePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "File path patterns (case-insensitive) blocked from pushing to non-fork remotes.";
    };
    fork.deniedMessagePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Commit message patterns (case-insensitive) blocked from pushing to non-fork remotes.";
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [ pkgs.jujutsu ];

    # jj stores repo config outside the repo tree; symlink to the generated store path
    enterShell = ''
      _jj_config_path="$(jj config path --repo 2>/dev/null)" || true
      if test -n "$_jj_config_path"; then
        ln -sfn ${jjRepoConfig} "$_jj_config_path"
      fi
      unset _jj_config_path
    '';

    # pre-push hook via devenv git-hooks
    git-hooks.hooks.jj-pre-push = {
      enable = true;
      name = "jj-pre-push";
      entry = "${prePushHook}/bin/jj-pre-push";
      stages = [ "pre-push" ];
      # pass all files — the hook reads from git stdin, not file args
      pass_filenames = false;
      always_run = true;
    };

    # Drop the jj-workflows agent rule into .claude/rules/
    files.".claude/rules/jj-workflows.md".source = ../../../docs/jj-workflows.md;
  };
}
