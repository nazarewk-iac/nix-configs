# Adopter template (den route) — a devenv shell that consumes one den aspect.
#
# Read docs/den-for-adopters.md first. This file is the minimum that works.
#
# THE API is `inputs.nix-configs.denModules.<aspect>`. Each entry is one already-resolved plain
# module. See `flake.denModules.gh` in modules/den/flake-module.nix. You pass no `pkgs`, no
# `specialArgs`, no `kdnConfig` and no overlay. One flake input, one `imports` entry, nothing else.
# Measured on 2026-09-11 from a directory outside the repository.
#
# 17 of the 20 aspects have a `denModules` entry. Three do not — `devenv-cli`, `llm-proxy` and
# `ssh-access` — because each one emits more than one class, and the zero-argument form names
# exactly one class. Reach those three through the library, which states the class:
#
#   imports = inputs.nix-configs.denLib.imports {
#     class = "devenv";
#     aspects = [ "gh" "ssh-access" ];
#   };
#
# NO OVERLAY. This is the one hard difference from templates/adopter/, the slots template. Seven
#   slots read `pkgs.kdn.*` and need `overlays.packages`. Every den aspect calls its own package
#   with a relative `pkgs.callPackage` path instead, so `pkgs.kdn` reaches no den aspect. Measured:
#   `grep -rn 'pkgs.kdn\.' modules/den/aspects/` returns comment lines only.
#
# NO `enable` OPTION. An aspect declares none. Inclusion in `imports` is the switch, so you turn an
#   aspect off by deleting its line. This is the biggest difference from the slot route, where every
#   slot carries `kdn.<slot>.enable`.
#
# WHAT THIS WRITES INTO YOUR REPOSITORY: one file, `.claude/settings.json`. The `gh` aspect sets
#   `claude.code.enable = lib.mkDefault true`, and devenv's Claude Code integration then writes that
#   file — see `settingsPath` and the `files` block in
#   <devenv>/src/modules/integrations/claude.nix:928,977. The file carries the read-only `gh` Bash
#   allowlist and nothing else. To stop the write, set `claude.code.enable = false;`. A plain value
#   beats `lib.mkDefault`, so you need no `lib.mkForce`. Measured on 2026-09-11.
#
# NO AGENT RULE FILE, unless you ask for one. Five aspects can install an agent rule or an agent
#   skill into your working tree: `jj`, `jj-fork`, `mcp-basic-memory`, `nix` and `zellij`. `jj`
#   installs the author's jj-only mandate, which forbids nearly all raw `git` use. Each of the five
#   gates its files behind its own `installAgentRules` option, and every one of the five defaults to
#   **false**. So you get no such file until you set the option. The slot route inverts this: there
#   `kdn.isSourceRepo = false` means "install them".
{
  inputs,
  ...
}:
{
  # One aspect as a worked example. `gh` is the smallest devenv-class aspect: it puts `pkgs.gh` on
  # PATH and it adds a read-only Bash allowlist for Claude Code. It needs no personal data, no
  # credential and no extra flake input, it carries no partial port, and it evaluates on Linux and
  # on macOS.
  imports = [ inputs.nix-configs.denModules.gh ];

  enterShell = ''
    echo "den adopter template: one aspect rendered, and no overlay"
  '';
}
