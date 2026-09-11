{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.nix;
  isSourceRepo = config.kdn.isSourceRepo;

  checkNixStoreSymlinks = pkgs.writeShellApplication {
    name = "check-nix-store-symlinks";
    runtimeInputs = [ pkgs.git ];
    text = builtins.readFile ./check-nix-store-symlinks.sh;
  };
in
{
  options.kdn.nix = {
    enable = lib.mkEnableOption "nix development tooling in devenv";

    installAgentRules = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install this slot's agent instruction files into the consumer repository.

        The files are `.claude/skills/flake-update/SKILL.md`,
        `.claude/skills/flake-patches/SKILL.md` and `.claude/rules/okf-format.md`.

        They state the author's own procedures: how to update a flake, how to keep a patch, and which
        frontmatter every markdown file carries. The default is false, so you get the files only when
        you ask for them. This repository turns the option on explicitly in its own `devenv.nix`.

        The option covers instruction files only. The packages, the git hooks and the MCP backends
        stay in place.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.mcp.programs.nixos.enable = true;
    kdn.mcp.extraBackends.devenv = {
      command = "devenv mcp";
      description = "devenv — search nixpkgs packages and devenv options";
      env.DEVENV_ROOT = toString inputs.nix-configs;
    };

    # A module function (not a plain attrset) so `config` here resolves against the real
    # devenv evaluation this fragment gets spliced into — needed for `config.git-hooks.package`,
    # which only exists there, not in the kdn-slots evaluation.
    devenv =
      { config, lib, ... }:
      {
        claude.code.enable = true;

        # Two deviations from devenv's default, and each one prevents a measured data loss.
        #
        # 1. The absolute store path. The default names `prek` alone, which fails outside a devenv
        #    shell, so Claude Code finds it whatever the PATH holds.
        #
        # 2. `--all-files`. Without it, prek stashes the unstaged changes around the run:
        #    `git rm --cached`, `git write-tree`, then **`git checkout -- <repo-root>`** over the
        #    whole working copy, then `git apply <patch>` to put the changes back
        #    (`prek/src/store/keeper.rs:45-54,90,145,157-189`).
        #
        #    In a colocated jj repository the git index holds the `@-` tree, plus an intent-to-add
        #    stub for each new file. So `write-tree` records the **parent** commit, `diff-index`
        #    reports the whole of `@` as unstaged, and the `checkout` discards the current jj
        #    change on every single edit. The restore is not reliable. It lives in `Drop`
        #    (`keeper.rs:220-228`) and `main.rs:462-472` installs a SIGINT handler only, so a
        #    SIGTERM leaves the tree reverted with no message. And a jj snapshot inside the ~10 ms
        #    window between `write-tree` and `diff-index` re-adds a new file as the empty blob, so
        #    the patch says `--- /dev/null`, the checkout writes 0 bytes, and the restoring
        #    `git apply` then fails with "already exists in working directory".
        #
        #    That checkout also rewrites `devenv.lock`, which is a watched path, so it wakes the
        #    devenv file watcher twice per edit. The rebuild then re-fetches `git+file:.` while
        #    prek's non-atomic writes are still in flight — that is the "unexpected end-of-file"
        #    symptom.
        #
        #    `--all-files` removes the writer instead of narrowing it.
        #    `requires_clean_worktree()` is false for `FileSelection::All`
        #    (`prek/src/cli/run/filter.rs:435-437`), so no `write-tree`, no `diff-index`, no
        #    `checkout` and no patch file run at all. No feedback is lost: both hooks this repo
        #    configures are `always_run` with `pass_filenames = false`, so a file list never
        #    reached them. Whole-suite runtime is 168 ms. Measured on 2026-09-10.
        claude.code.hooks.git-hooks-run.command =
          ''cd "$DEVENV_ROOT" && ${lib.getExe config.git-hooks.package} run --all-files'';

        # Restore the upstream matcher. devenv scopes git-hooks-run to file edits by default
        # (^(Edit|MultiEdit|Write)$). But the command override above defines the submodule, so
        # each unset field falls back to its per-field default, and `matcher` resets to "" (every
        # tool). An empty matcher then runs the hook after EVERY tool call, including a read-only
        # one during a long build. Scope it back to the file edits.
        claude.code.hooks.git-hooks-run.matcher = "^(Edit|MultiEdit|Write)$";

        # Read-only/evaluation-only commands — safe to always allow, no side effects. `nix run`
        # itself is deliberately NOT allowed as a bare wildcard (it executes arbitrary flake apps);
        # only this repo's own idempotent formatter is allow-listed by exact invocation.
        claude.code.permissions.rules.Bash.allow = [
          "nix build *"
          "nix eval *"
          "nix flake metadata*"
          "nix flake show *"
          "nix search *"
          "nix path-info *"
          "nix log *"
          "nix why-depends *"
          "devenv build *"
          "devenv eval *"
          "nix run .#kdn-nix-fmt -- *"
        ];

        packages = with pkgs; [
          nil
          nixd
          nixfmt
        ];

        git-hooks.hooks.check-nix-store-symlinks = {
          enable = true;
          name = "check-nix-store-symlinks";
          description = "Reject commits that include symlinks into /nix/store (managed by devenv/NixOS/HM)";
          entry = lib.getExe checkNixStoreSymlinks;
          stages = [
            "pre-commit"
            "pre-push"
          ];
          pass_filenames = false;
          always_run = true;
        };

        files = lib.mkIf (cfg.installAgentRules && !isSourceRepo) {
          ".claude/skills/flake-update/SKILL.md".source =
            "${inputs.nix-configs}/.agents/skills/flake-update/SKILL.md";
          ".claude/skills/flake-patches/SKILL.md".source =
            "${inputs.nix-configs}/.agents/skills/flake-patches/SKILL.md";
          ".claude/rules/okf-format.md".source = "${inputs.nix-configs}/.agents/rules/okf-format.md";
        };

        scripts.hello.exec = ''
          echo "hello from nix-configs devenv"
        '';
      };
  };
}
