# The first `devenv`-target aspect. It ports `modules/slots/gh/default.nix`.
#
# The slot stays in place and keeps working. This aspect carries the same three facts: the package,
# the Claude Code opt-in, and the read-only Bash allowlist.
#
# The allowlist covers read-only, side-effect-free subcommands only. It deliberately holds no
# `gh api *` — that is a generic REST passthrough and it mutates with `-X POST`. It holds no
# `gh auth login|refresh|logout`, and no create, edit, close, merge or comment subcommand.
#
# The aspect takes no entity argument, so `den.lib.aspects.resolve` returns a real module across
# the export boundary. An aspect that reads entity data resolves to `{ imports = [ ]; }` in
# silence — see the guard in ../flake-module.nix.
{ ... }:
{
  den.aspects.gh.devenv =
    { pkgs, lib, ... }:
    {
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
}
