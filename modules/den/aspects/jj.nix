# The `jj` slot, as a den aspect. It ports `modules/slots/jj/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives a devenv shell the `jj` binary, one generated jj **repo** config file, a read-only Bash
# allowlist for Claude Code, one `PreToolUse` hook that warns on a raw `git` call, one agent, and two
# agent files. It also adds one MCP backend, `jj-mcp`, and it turns the gateway's own `git` backend
# off.
#
# ## Why it includes `mcp`
#
# The slot writes `kdn.mcp.extraBackends.jj` and `kdn.mcp.programs.git.enable`, so one slot
# configures another slot's option. `includes` is the aspect answer: it puts both target modules into
# one evaluation, so this file writes the parent's option directly and needs no shared declaration
# file. den collapses the diamond, so a shell that also includes another `mcp` child still holds one
# gateway. See ./mcp.nix.
#
# ## The coupled pair
#
# `./jj-fork.nix` names this aspect in its own `includes`. It holds every fork-remote feature: the
# revset aliases, the two sync aliases, the two git hooks and the two audit commands. So an entity
# with no private fork includes this aspect alone, and an entity with one includes `jj-fork`.
#
# The split follows one rule: **an option belongs in the aspect that reads it.** This file declares
# `kdn.jj.upstream.*` and `kdn.jj.config`, because its own `enterShell` reads both. `jj-fork.nix`
# declares `kdn.jj.fork.*` and `kdn.jj.alwaysBlockedMessagePatterns`, because only its own scripts
# read them. Both option paths stay exactly as the slot spells them.
#
# ## The de-personalized port
#
# `kdn.jj.upstream.remote` defaulted to one person's own remote name. A default like that reaches
# every adopter and every generated script, so the aspect defaults to `"origin"` instead. The
# consumer names its own remote. See gap 6 of
# ../../../docs/tasks/2026-09/generalization/definition.md.
#
# ## The agent files carry this repository's own opinion
#
# The rule, the skill and the agent prompt state a jj-only mandate and this repository's own fork
# workflow. So an adopter that uses plain git gets an opinion it did not ask for. Two switches now
# gate all three: `kdn.isSourceRepo`, and `kdn.jj.installAgentRules`. The second one defaults to
# false, so an adopter opts in with one line, and this repository turns it on explicitly. It
# covers the three files only — the `jj-guard` hook, the Bash allowlist and the `jj` package stay.
# See ../../../docs/tasks/2026-09/generalization/013-opt-in-boundaries/definition.md, rows 45 and 46.
#
# ## Three files, each a relative path literal
#
# The slot reads `jj-guard.sh` from its own directory. It reads the rule, the skill and the agent
# prompt through `"${inputs.nix-configs}/…"`, and each one of those is a second whole-tree store
# copy. Every read here is a relative path literal, so the derivation depends on one file and not on
# the whole tree. See
# ../../../docs/tasks/2026-09/generalization/011-whole-tree-store-copies/definition.md.
#
# ## Where the shell script moves later
#
# This aspect reads `jj-guard.sh` from the slot directory. The creator's instruction on 2026-09-10
# keeps every file in place for now. A duplicate copy drifts in silence, and a dangling path fails
# loudly, so den reads the slot's copy. When the slot tree goes away, the script moves to
# `modules/den/aspects/jj/` and this file becomes a directory. See
# ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## What the port keeps unchanged
#
# `jj-guard.sh` warns and never blocks, and it cannot see Claude Code's own `/commit` slash command.
# That limit is a property of the hook interface, not of the port, so this aspect states it and keeps
# the script as it is.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.jj.enable` is gone.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only —
#    the arguments every NixOS, nix-darwin, home-manager and devenv evaluation already gives. An
#    argument such as `inputs` would force the consumer to pass `specialArgs`. The slot reads
#    `inputs` for three file paths; this target reads none.
{ kdn, ... }:
{
  kdn.jj.includes = [ kdn.mcp ];

  kdn.jj.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.jj;

      # A plain `callPackage` route, with no overlay. The slot reads `pkgs.kdn.jj-mcp`, so a consumer
      # must add this repository's `packages` overlay first. A relative path needs no overlay, and it
      # stays inside the tree the evaluation already reads. ./zellij.nix carries the same pattern.
      jj-mcp = pkgs.callPackage ../../../packages/jj-mcp { };

      # Every `kdn.jj.config` fragment, from this aspect and from ./jj-fork.nix, lands in one TOML
      # file. `enterShell` points `jj config path --repo` at it.
      jjRepoConfig = (pkgs.formats.toml { }).generate "jj-repo-config.toml" cfg.config;

      jjGuardHook = pkgs.writeShellApplication {
        name = "jj-guard";
        runtimeInputs = [ pkgs.jq ];
        text = builtins.readFile ../../slots/jj/jj-guard.sh;
      };
    in
    {
      # One declaration of `kdn.isSourceRepo`, imported by path. The module system rejects two inline
      # declarations of one option, and it drops a repeated import by path. See ../common/.
      imports = [ ../common/source-repo.nix ];

      options.kdn.jj.installAgentRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install this aspect's agent instruction files into the consumer repository.

          The files are `.claude/rules/jujutsu-vcs.md`, `.claude/skills/jujutsu-vcs/SKILL.md` and the
          `jj-expert` Claude Code subagent.

          They state the author's own work mandate: never use raw `git`, always use `jj`. The default
          is false, so you get the files only when you ask for them. This repository turns the option
          on explicitly in `checks/den-mvp/devenv/default.nix`.

          The option covers instruction files only. The `jj-guard` hook, the Bash allowlist and the
          `jj` package stay in place.
        '';
      };

      options.kdn.jj.upstream.remote = lib.mkOption {
        type = lib.types.str;
        default = "origin";
        description = ''
          Name of the public remote — the one every published change reaches.

          The slot defaulted this to one person's own remote name, so every adopter inherited it and
          every generated script carried it. The default here names no person. A consumer sets its
          own name, and ./jj-fork.nix reads the same value for the public half of the fork topology.
        '';
        example = "public";
      };

      options.kdn.jj.upstream.url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          URL of the public remote. A non-null value makes `enterShell` add the remote when the
          repository does not hold it yet. `null` adds nothing.
        '';
      };

      options.kdn.jj.config = lib.mkOption {
        type = (pkgs.formats.toml { }).type;
        default = { };
        description = ''
          Freeform jj **repo** config, as TOML. The aspect generates one file from it, and
          `enterShell` symlinks `jj config path --repo` at that file.

          A sibling aspect adds a fragment here instead of a second file of its own. ./jj-fork.nix is
          the one writer in this tree, and it contributes the revset aliases and the sync aliases.
        '';
      };

      config = {
        kdn.jj.config."#schema" = "https://docs.jj-vcs.dev/latest/config-schema.json";

        # Both writes below belong to the `mcp` aspect's own options. `includes` puts that aspect's
        # target module into this same evaluation, so this file writes them directly.
        #
        # The gateway's own `git` backend stays off. It duplicates the jj backend for a colocated
        # repository, and it names git operations that this repository forbids.
        # Each leaf is a `lib.mkDefault`, so a consumer repoints the backend, or re-enables the
        # gateway's own `git` backend, with a plain assignment. The paired slot matches.
        kdn.mcp.extraBackends.jj.command = lib.mkDefault "${jj-mcp}/bin/jj-mcp";
        kdn.mcp.extraBackends.jj.description =
          lib.mkDefault "jj — Jujutsu version control tools";
        kdn.mcp.programs.git.enable = lib.mkDefault false;

        packages = [ pkgs.jujutsu ];

        enterShell = ''
          # Point `jj config path --repo` at the generated file. Every `kdn.jj.*` aspect merges into
          # it.
          #
          # `jj config path --repo` returns ONE shared file for the default workspace and for every
          # secondary workspace. The id in the path comes from `.jj/repo/config-id`, and a secondary
          # workspace reaches the same store through a `.jj/repo` pointer file. So a `devenv shell`
          # in a secondary workspace would write over the default workspace's config and drop its
          # aliases. Only the default workspace writes the file.
          #
          # The test asks whether this is a SECONDARY workspace, not whether it is the default one.
          # `.jj/repo` is a directory in the default workspace and a small pointer file in a
          # secondary one. So a future jj layout change makes this shell write the file, which is
          # today's behaviour, and it never makes the default workspace lose its config.
          _jj_config_path="$(jj config path --repo 2>/dev/null)" || true
          _jj_root="$(jj root 2>/dev/null)" || true
          if test -n "$_jj_root" && test -f "$_jj_root/.jj/repo"; then
            echo "kdn.jj: secondary jj workspace — the shared jj repo config stays untouched" >&2
          elif test -n "$_jj_config_path"; then
            ln -sfn ${jjRepoConfig} "$_jj_config_path"
          fi
          unset _jj_config_path _jj_root

          # Add a remote by name and URL through jj itself, with no git CLI, when it is absent.
          # ./jj-fork.nix calls this function too, from an `enterShell` that runs after this one.
          _kdn_jj_ensure_remote() {
            local remote="$1" url="$2"
            if ! jj git remote list | cut -d' ' -f1 | grep -qxF "$remote"; then
              jj git remote add "$remote" "$url"
            fi
          }

          ${lib.optionalString (cfg.upstream.url != null) ''
            _kdn_jj_ensure_remote ${lib.escapeShellArg cfg.upstream.remote} ${lib.escapeShellArg cfg.upstream.url}
          ''}
        '';

        claude.code.enable = lib.mkDefault true;

        # A warning, never a block. The hook prints the jj equivalent of the raw `git` call and it
        # allows the call. It cannot intercept Claude Code's own `/commit` slash command, which
        # shells a raw `git commit` internally, so it is one net and not the gate.
        claude.code.hooks.jj-guard = {
          hookType = "PreToolUse";
          matcher = "Bash";
          command = ''cd "$DEVENV_ROOT" && ${lib.getExe jjGuardHook}'';
        };

        # Read-only jj subcommands. Each one is free of side effects.
        #
        # Every rule is deliberately narrower than a bare `jj file *` or `jj config *` would be: both
        # hold mutating subcommands (`chmod`, `track`, `untrack`, `set`, `unset`, `edit`) that must
        # stay behind a normal permission prompt.
        #
        # The list also holds the read-only git exceptions that `jj-guard.sh` names in its own
        # `ALLOWED_READONLY` string. Keep the two in step. Those `git *` rules belong to git as a
        # tool, not to jj, so they move to a `git` aspect when one exists.
        claude.code.permissions.rules.Bash.allow = [
          "jj --help"
          "jj help*"
          "jj * --help"
          "jj log *"
          "jj diff *"
          "jj status*"
          "jj show *"
          "jj file show *"
          "jj file list *"
          "jj config get *"
          "jj config list *"
          "jj config path*"
          "jj op log*"
          "jj bookmark list *"
          "git status*"
          "git diff *"
          "git log *"
          "git show *"
          "git check-ignore *"
        ];

        # One agent, and two agent files. Each source is a relative path literal, so the derivation
        # reads one file. See the header.
        #
        # The slot also sets `proactive = true`. devenv removed that option on 2026-08-16, and it
        # turns a definition into a hard assertion failure. So a literal port does not evaluate. The
        # migration devenv prescribes is a phrase in the description, and this line carries it. See
        # `<devenv>/src/modules/integrations/claude.nix:367,958`.
        #
        # The slot never hits the assertion, because it gates the agent on `kdn.isSourceRepo` and
        # this repository sets that flag true. A consumer with the flag false gets the failure. That
        # is a slot defect, and it needs its own commit.
        claude.code.agents = lib.mkIf (cfg.installAgentRules && !config.kdn.isSourceRepo) {
          jj-expert = {
            description = "Deep jj (Jujutsu VCS) troubleshooting: divergent changes, conflicts, graph surgery, revset/fileset/template questions. Use proactively.";
            prompt = builtins.readFile ../../../.agents/agents/jj-expert/AGENT.md;
          };
        };

        files = lib.mkIf (cfg.installAgentRules && !config.kdn.isSourceRepo) {
          ".claude/rules/jujutsu-vcs.md".source = ../../../.agents/rules/jujutsu-vcs.md;
          ".claude/skills/jujutsu-vcs/SKILL.md".source = ../../../.agents/skills/jujutsu-vcs/SKILL.md;
        };

        # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
        #
        # devenv puts this in `config.enterTest`, and `config.test` wraps it as a script. It runs
        # under `devenv test` and under `checks.<system>.den-smoke-*`. It never runs on shell entry,
        # and it never runs during a nix-darwin or a NixOS activation.
        #
        # Every assertion stays offline. The check runs inside the build sandbox, which has no
        # network, no real `$HOME` and no jj repository. So no assertion runs a repository command.
        #
        # ./mcp.nix already greps the generated gateway YAML for every backend name, so the backend
        # this aspect adds reaches that assertion with no line here.
        enterTest = ''
          echo "• jj: the binary reports a version" >&2
          jj --version | grep -qE '^jj [0-9]+\.'

          echo "• jj: the generated repo config names the schema" >&2
          grep -Fq 'config-schema.json' ${jjRepoConfig}

          echo "• jj: the raw-git guard hook is executable" >&2
          test -x ${lib.getExe jjGuardHook}

          echo "• jj: the MCP backend binary exists" >&2
          test -x ${jj-mcp}/bin/jj-mcp
        '';
      };
    };
}
