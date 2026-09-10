# The `nix` slot, as a den aspect. It ports `modules/slots/nix/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives a devenv shell the two Nix language servers and the formatter, a read-only Bash allowlist
# for Claude Code, one pre-commit hook, two agent skills and one agent rule. It also adds two MCP
# backends: the `nixos` option search, and `devenv mcp`.
#
# ## Why it includes `mcp`
#
# The slot writes `kdn.mcp.programs.nixos.enable` and `kdn.mcp.extraBackends.devenv`, so one slot
# configures another slot's option. `includes` is the aspect answer: it puts both target modules into
# one evaluation, so this file writes the parent's option directly and needs no shared declaration
# file. den collapses the diamond, so a shell that also includes another `mcp` child still holds one
# gateway. See ./mcp.nix.
#
# ## The `DEVENV_ROOT` defect the port fixes
#
# The slot sets `env.DEVENV_ROOT = toString inputs.nix-configs` on the `devenv` backend. That freezes
# a **read-only store copy** of the whole repository, so `devenv mcp` answers against a tree that no
# edit reaches. It is also a whole-tree store copy — see
# ../../../docs/tasks/2026-09/generalization/011-whole-tree-store-copies/definition.md.
#
# A wrapper script replaces it. The script reads `DEVENV_ROOT` at run time, so the backend always
# sees the real working tree. ./mcp.nix uses the same pattern for the gateway command. The wrapper
# needs no fallback option: `DEVENV_ROOT` is always set in the shell that starts Claude Code, and a
# missing value must fail loudly instead of pointing at the wrong tree.
#
# ## Four repository files, each a relative path literal
#
# The slot reads `check-nix-store-symlinks.sh` from its own directory. It reads two skills and one
# rule through `"${inputs.nix-configs}/…"`. Every read here is a relative path literal, so the
# derivation depends on one file and not on the whole tree.
#
# The two skills describe **this repository's own fork update workflow**. So an adopter with no fork
# gets two skills it does not use. They install anyway, with `kdn.isSourceRepo` as the only switch,
# exactly as every other ported aspect installs its own files. A `fork` option belongs to the `jj`
# family, and that family is a later port.
#
# ## Where the shell script moves later
#
# This aspect reads `check-nix-store-symlinks.sh` from the slot directory. The creator's instruction
# on 2026-09-10 keeps every file in place for now. A duplicate copy drifts in silence, and a dangling
# path fails loudly, so den reads the slot's copy. When the slot tree goes away, the script moves to
# `modules/den/aspects/nix/` and this file becomes a directory. See
# ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## What the port drops
#
# `scripts.hello.exec` printed one line that names this repository. It carries no technical value and
# it tests nothing, so this aspect ships no such script.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.nix.enable` is gone.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only —
#    the arguments every NixOS, nix-darwin, home-manager and devenv evaluation already gives. An
#    argument such as `inputs` would force the consumer to pass `specialArgs`. The slot reads `pkgs`
#    and `config` from its outer arguments; this target reads its own.
{ kdn, ... }:
{
  kdn.nix.includes = [ kdn.mcp ];

  kdn.nix.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.nix;

      checkNixStoreSymlinks = pkgs.writeShellApplication {
        name = "check-nix-store-symlinks";
        runtimeInputs = [ pkgs.git ];
        text = builtins.readFile ../../slots/nix/check-nix-store-symlinks.sh;
      };

      # The `devenv mcp` backend command. The slot froze a store path into `env.DEVENV_ROOT`; this
      # wrapper reads the variable at run time instead, so the backend serves the real working tree.
      devenvMcpWrapper = pkgs.writeShellScript "devenv-mcp-wrapper" ''
        cd "''${DEVENV_ROOT:?the devenv MCP backend needs DEVENV_ROOT}"
        exec ${lib.getExe pkgs.devenv} mcp
      '';
    in
    {
      # One declaration of `kdn.isSourceRepo`, imported by path. The module system rejects two inline
      # declarations of one option, and it drops a repeated import by path. See ../common/.
      imports = [ ../common/source-repo.nix ];

      options.kdn.nix.extraBashAllow = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Extra Claude Code Bash allow rules, next to the read-only `nix` and `devenv` rules below.

          The slot allow-listed one flake app of this repository by exact invocation. An app name
          belongs to the consumer, not to a reusable aspect, so the consumer names its own here.

          Keep every rule read-only or idempotent. A bare `nix run *` wildcard executes an arbitrary
          flake app, so it must never enter this list.
        '';
        example = [ "nix run .#my-formatter -- *" ];
      };

      config = {
        # Both writes below belong to the `mcp` aspect's own options. `includes` puts that aspect's
        # target module into this same evaluation, so this file writes them directly.
        kdn.mcp.programs.nixos.enable = true;
        kdn.mcp.extraBackends.devenv = {
          command = "${devenvMcpWrapper}";
          description = "devenv — search nixpkgs packages and devenv options";
        };

        packages = [
          pkgs.nil
          pkgs.nixd
          pkgs.nixfmt
        ];

        claude.code.enable = lib.mkDefault true;

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
        #    reports the whole of `@` as unstaged, and the `checkout` discards the current jj change
        #    on every single edit. The restore is not reliable. It lives in `Drop`
        #    (`keeper.rs:220-228`) and `main.rs:462-472` installs a SIGINT handler only, so a SIGTERM
        #    leaves the tree reverted with no message. And a jj snapshot inside the ~10 ms window
        #    between `write-tree` and `diff-index` re-adds a new file as the empty blob, so the patch
        #    says `--- /dev/null`, the checkout writes 0 bytes, and the restoring `git apply` then
        #    fails with "already exists in working directory".
        #
        #    That checkout also rewrites `devenv.lock`, which is a watched path, so it wakes the
        #    devenv file watcher twice per edit. The rebuild then re-fetches `git+file:.` while
        #    prek's non-atomic writes are still in flight — that is the "unexpected end-of-file"
        #    symptom.
        #
        #    `--all-files` removes the writer instead of narrowing it.
        #    `requires_clean_worktree()` is false for `FileSelection::All`
        #    (`prek/src/cli/run/filter.rs:435-437`), so no `write-tree`, no `diff-index`, no
        #    `checkout` and no patch file run at all. No feedback is lost: every hook here is
        #    `always_run` with `pass_filenames = false`, so a file list never reached it.
        #    Whole-suite runtime is 168 ms. Measured on 2026-09-10.
        #
        # `config.git-hooks.package` is the consumer's own evaluated value. devenv already declares
        # it as `lib.mkDefault pkgs.prek`, so this aspect adds no default of its own.
        claude.code.hooks.git-hooks-run.command =
          ''cd "$DEVENV_ROOT" && ${lib.getExe config.git-hooks.package} run --all-files'';

        # Restore the upstream matcher. devenv scopes `git-hooks-run` to a file edit by default
        # (`^(Edit|MultiEdit|Write)$`). But the command override above defines the submodule, so each
        # unset field falls back to its per-field default, and `matcher` resets to "" (every tool).
        # An empty matcher then runs the hook after EVERY tool call, including a read-only one during
        # a long build. Scope it back to the file edits.
        claude.code.hooks.git-hooks-run.matcher = "^(Edit|MultiEdit|Write)$";

        # Read-only and evaluation-only commands. Each one is free of side effects. `nix run` is
        # deliberately absent as a wildcard, because it executes an arbitrary flake app. A consumer
        # allow-lists its own app by exact invocation through `kdn.nix.extraBashAllow`.
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
        ]
        ++ cfg.extraBashAllow;

        git-hooks.hooks.check-nix-store-symlinks = {
          enable = true;
          name = "check-nix-store-symlinks";
          description = "Reject a commit that holds a symlink into /nix/store (devenv, NixOS or HM manages it)";
          entry = lib.getExe checkNixStoreSymlinks;
          stages = [
            "pre-commit"
            "pre-push"
          ];
          pass_filenames = false;
          always_run = true;
        };

        # One file per entry, not a whole tree. See the header.
        files = lib.mkIf (!config.kdn.isSourceRepo) {
          ".claude/skills/flake-update/SKILL.md".source = ../../../.agents/skills/flake-update/SKILL.md;
          ".claude/skills/flake-patches/SKILL.md".source = ../../../.agents/skills/flake-patches/SKILL.md;
          ".claude/rules/okf-format.md".source = ../../../.agents/rules/okf-format.md;
        };

        # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
        #
        # devenv puts this in `config.enterTest`, and `config.test` wraps it as a script. It runs
        # under `devenv test` and under `checks.<system>.den-smoke-*`. It never runs on shell entry,
        # and it never runs during a nix-darwin or a NixOS activation.
        #
        # Every assertion stays offline. The check runs inside the build sandbox, which has no
        # network, no real `$HOME` and no git repository. So no assertion starts a language server
        # and no assertion runs the pre-commit suite.
        #
        # ./mcp.nix already greps the generated gateway YAML for every backend name, so the two
        # backends this aspect adds reach that assertion with no line here.
        enterTest = ''
          echo "• nix: both language servers and the formatter report a version" >&2
          nil --version | grep -qE '^nil '
          nixd --version | grep -qE '^nixd'
          nixfmt --version | grep -qE '^nixfmt '

          echo "• nix: the devenv MCP backend runs a wrapper that reads DEVENV_ROOT at run time" >&2
          test -x ${devenvMcpWrapper}
          grep -Fq 'DEVENV_ROOT' ${devenvMcpWrapper}

          echo "• nix: the store-symlink hook entry is executable" >&2
          test -x ${lib.getExe checkNixStoreSymlinks}
        '';
      };
    };
}
