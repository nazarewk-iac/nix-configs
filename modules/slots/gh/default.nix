# GitHub CLI (gh) devenv slot.
#
# Installs the gh package. The Bash permission allowlist below intentionally covers ONLY
# read-only, side-effect-free subcommands observed in actual agent usage across past sessions
# (pr/issue view+diff, search, repo/release view, auth status) plus `--help`/`help`. It
# deliberately does NOT allow-list `gh api *` — that's a generic REST/GraphQL passthrough that
# can mutate via `-X POST/PATCH/DELETE` or `--input`, so it stays behind normal permission
# prompts — nor `gh auth login|refresh|logout` (credential/scope mutation), nor any
# create/edit/close/merge/comment subcommand.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.gh;
in
{
  options.kdn.gh = {
    enable = lib.mkEnableOption "GitHub CLI (gh) devenv integration";
  };

  config = lib.mkIf cfg.enable {
    devenv = {
      packages = [ pkgs.gh ];

      claude.code.enable = lib.mkDefault true;

      claude.code.permissions.rules.Bash.allow = [
        "gh --help"
        "gh help*"
        "gh * --help"
        "gh auth status*"
        "gh pr view *"
        "gh pr diff *"
        "gh pr list *"
        "gh pr checks *"
        "gh issue view *"
        "gh issue list *"
        "gh repo view *"
        "gh release view *"
        "gh release list *"
        "gh run view *"
        "gh run list *"
        "gh search issues *"
        "gh search prs *"
        "gh search repos *"
        "gh search code *"
      ];
    };
  };
}
