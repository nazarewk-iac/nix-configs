{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.jj;

  jjRepoConfig = (pkgs.formats.toml { }).generate "jj-repo-config.toml" {
    "#schema" = "https://docs.jj-vcs.dev/latest/config-schema.json";
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

    enterShell = ''
      # symlink jj repo config to the generated store path
      _jj_config_path="$(jj config path --repo 2>/dev/null)" || true
      if test -n "$_jj_config_path"; then
        ln -sfn ${jjRepoConfig} "$_jj_config_path"
      fi
      unset _jj_config_path

      ${lib.optionalString (cfg.upstream.url != null) ''
        # add upstream remote if missing
        if ! git remote get-url ${lib.escapeShellArg cfg.upstream.remote} &>/dev/null; then
          git remote add ${lib.escapeShellArg cfg.upstream.remote} ${lib.escapeShellArg cfg.upstream.url}
        fi
      ''}
    '';

    files = lib.mkMerge [
      (lib.mkIf (!config.kdn.isSourceRepo) {
        ".claude/rules/jj-workflows.md".source = "${inputs.nix-configs}/.agents/rules/jj-workflows.md";
        ".claude/skills/jj-workflows/SKILL.md".source =
          "${inputs.nix-configs}/.agents/skills/jj-workflows/SKILL.md";
      })
    ];

    kdn.mcp.extraBackends.jj = {
      command = "${pkgs.kdn.jj-mcp}/bin/jj-mcp";
      description = "jj — Jujutsu version control tools";
    };
    kdn.mcp.programs.git.enable = false;
  };
}
