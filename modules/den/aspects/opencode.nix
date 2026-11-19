# The `opencode` slot, as a den aspect. It ports `modules/slots/opencode/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on devenv's own `opencode` integration, so devenv writes a project-level
# `opencode.jsonc`. opencode deep-merges that file over the user's global configuration, so a
# value this aspect does not set stays as the user set it.
#
# It also puts **one** binary named `opencode` on PATH: a wrapper. The wrapper exports the
# credentials, then it execs the real opencode by absolute store path. The real binary never
# reaches the bare PATH, so a plain `opencode` call can never skip the credential step.
# `KDN_OPENCODE_WRAPPER=1` tells the running opencode that a wrapper started it.
#
# ## The aspect holds the shape; the consumer holds the data
#
# The slot hardcodes three of the creator's own values: one commercial provider name in the
# credential read, that same provider in the default `settings`, and the creator's checkout path
# `~/dev/**` in five permission blocks. This aspect names none of them. It declares an option for
# each, and the consumer supplies the value:
#
# | Data | Option |
# |---|---|
# | which provider key to read, and into which environment variable | `kdn.opencode.authKeys` |
# | which provider block to write | `kdn.opencode.settings` |
# | which paths a tool may reach with no question | `kdn.opencode.allowedPaths` |
#
# The creator stated this constraint on 2026-09-10: an aspect stays universal, and the data stays
# with the consumer. See ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## One behaviour that differs from the slot, on purpose
#
# The slot puts the permission baseline **inside** the `settings` default. A `default` disappears
# the moment any definition exists, so a consumer that sets one provider silently loses the whole
# baseline. This aspect merges the baseline in the `config` instead. So the baseline always applies,
# and a consumer overrides it only by setting `settings.permission` itself.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. So an inclusion means "this shell runs
#    opencode".
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.opencode.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.opencode;

      # The permission baseline. It is a policy, not personal data: it asks before every write and
      # before every reach outside the project, and it allows a read of the paths the consumer
      # named. `lib.genAttrs` keeps the four read-only tools in step with one list.
      allowMap = lib.listToAttrs (map (p: lib.nameValuePair p "allow") cfg.allowedPaths);

      defaultPermission = {
        external_directory = {
          "*" = "ask";
        }
        // allowMap;
        edit = "ask";
        bash = {
          "cat *" = "allow";
          "ls *" = "allow";
          "grep *" = "allow";
          "rg *" = "allow";
          "head *" = "allow";
          "tail *" = "allow";
          "wc *" = "allow";
          "sort *" = "allow";
          "find *" = "allow";
          "stat *" = "allow";
          "file *" = "allow";
          "git status*" = "allow";
          "*" = "ask";
        };
      }
      // lib.genAttrs [
        "read"
        "glob"
        "grep"
        "list"
      ] (_: allowMap);

      # One export per credential. Each value is a provider id in opencode's own `auth.json`, so
      # the jq filter reads `.<provider>.key`. An empty attribute set emits no line at all, so the
      # aspect names no provider by itself.
      authExports = lib.mapAttrsToList (name: provider: ''
        export ${name}="$(${lib.getExe pkgs.jq} -r ${lib.escapeShellArg ".${provider}.key // empty"} "${cfg.authFile}" 2>/dev/null || true)"
        if [ -z "''${${name}:-}" ]; then
          echo "opencode: the kdn wrapper found no ${provider} key in ${cfg.authFile}" >&2
        fi
      '') cfg.authKeys;

      # opencode injects the current date into the system prompt (a `Today's date:` line in its
      # `<env>` block). The date changes at midnight, so the prompt prefix changes and a
      # server-side KV/prompt cache cannot reuse it. On a hybrid (recurrent) local model that
      # forces a full re-prefill of the whole conversation. This plugin replaces the date with a
      # stable line that points at the `current-date` skill, so the prompt stays byte-stable and
      # the model still knows how to obtain the date on demand.
      #
      # The hook is `experimental` and opencode-v1 only; it is guarded so a missing or renamed
      # hook never breaks a request. See docs/tasks/2026-10/opencode-stable-system-prompt/.
      stablePromptPlugin = ''
        import { Plugin } from "@opencode/plugin"

        // Generated by the kdn.opencode aspect. See
        // docs/tasks/2026-10/opencode-stable-system-prompt/.
        //
        // opencode injects the current date into the system prompt (a
        // `Today's date:` line in its <env> block). The date changes at
        // midnight, so the prompt prefix changes and a server-side KV/prompt
        // cache cannot reuse it. On a hybrid (recurrent) local model that
        // forces a full re-prefill of the whole conversation. This plugin
        // replaces the date with a stable line that points at the
        // `current-date` skill, so the prompt stays byte-stable and the model
        // still knows how to obtain the date on demand.
        //
        // OpenCode 2 replaced the V1 `experimental.chat.system.transform` hook
        // with the `context` session hook. Each system entry is a part object
        // (`{ type: "text", text }`), so the rewrite edits `part.text` in place
        // and leaves the array identity alone.

        const DATE_LINE = /^([ \t]*)Today's date:.*$/gm
        const STABLE_DATE_LINE = "$1Today's date: not injected (kept out of the prompt so it stays stable); use the `current-date` skill when you need it."

        export default Plugin.define({
          id: "kdn.stable-system-prompt",
          async setup(ctx) {
            await ctx.session.hook("context", (event) => {
              for (const part of event.system) {
                if (typeof part === "string") continue
                if (!part || part.type !== "text" || typeof part.text !== "string") continue
                part.text = part.text.replace(DATE_LINE, STABLE_DATE_LINE)
              }
            })
          },
        })
      '';

      # The plugin replaces the date line with a pointer to the `current-date` skill. The skill
      # itself is tracked repo content at `.opencode/skills/current-date/SKILL.md` (it is
      # opencode-specific, so it lives in `.opencode/`, not `.agents/skills/`). It is not
      # generated here, so git can track it. See
      # docs/tasks/2026-10/opencode-stable-system-prompt/.
      # The ClankTalk shim. It is a folder plugin: OpenCode loads `index` for the server part and
      # `tui` beside it. The upstream plugin adds `clank_talk` in `setup` before it checks the mode,
      # so a normal session must not call `setup` at all. `clank-opencode` sets KDN_CLANK_TALK.
      clankTalkPlugin = "${cfg.clankTalk.package}/lib/clank-talk/src/js/harnesses/opencode";

      clankTalkIndex = ''
        // Generated by the kdn.opencode aspect. Load the upstream ClankTalk plugin only when the
        // clank-opencode launcher sets KDN_CLANK_TALK. See docs/clank-talk.md.
        import upstream from ${builtins.toJSON "${clankTalkPlugin}/index.js"}

        export default {
          id: "kdn.clank-talk",
          async setup(ctx) {
            if (process.env.KDN_CLANK_TALK !== "1") return
            return upstream.setup(ctx)
          },
        }
      '';

      clankTalkTui = ''
        // Generated by the kdn.opencode aspect. The TUI part of the ClankTalk shim: it must be
        // gated too, or a normal session gets `/clank-talk` and `/taint` commands that cannot work.
        import upstream from ${builtins.toJSON "${clankTalkPlugin}/tui.js"}

        export default {
          id: "kdn.clank-talk.tui",
          async setup(ctx, options) {
            if (process.env.KDN_CLANK_TALK !== "1") return
            return upstream.setup(ctx, options)
          },
        }
      '';

      # OpenCode 2.2.5 discovers an immediate plugin package directory under `.opencode/plugins/`,
      # but it does not load a folder whose `index.js`/`tui.js` are Nix store symlinks. The files are
      # therefore installed as regular copies by `enterShell`, not through `devenv.files`.
      clankTalkIndexFile = pkgs.writeText "kdn-clank-talk-index.js" clankTalkIndex;
      clankTalkTuiFile = pkgs.writeText "kdn-clank-talk-tui.js" clankTalkTui;
      clankTalkPackageFile = pkgs.writeText "kdn-clank-talk-package.json" (
        builtins.toJSON {
          name = "kdn-clank-talk";
          version = "0.0.0";
          type = "module";
          exports = {
            "." = "./index.js";
            "./tui" = "./tui.js";
          };
        }
      );

      opencodeBin = pkgs.writeShellScriptBin "opencode" ''
        set -euo pipefail
        export KDN_OPENCODE_WRAPPER=1
        ${lib.concatStringsSep "\n" authExports}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.wrapper.env
        )}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: path: ''export ${name}="$(cat ${path})"'') cfg.wrapper.envFiles
        )}
        ${cfg.wrapper.preExec}
        exec ${lib.getExe cfg.package} "$@"
      '';
    in
    {
      options.kdn.opencode.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.opencode;
        defaultText = lib.literalExpression "pkgs.opencode";
        description = ''
          The real opencode binary that the wrapper execs. It never reaches the bare PATH; the
          wrapper carries the name `opencode` instead.
        '';
      };

      options.kdn.opencode.defaultModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "some-provider/some-model";
        description = ''
          The model written to `opencode.jsonc` as `model`. When null, the key stays out of the
          file, so an existing model choice keeps its value.
        '';
      };

      options.kdn.opencode.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = lib.literalExpression ''
          {
            provider.some-provider = { };
          }
        '';
        description = ''
          The content of `opencode.jsonc`, written verbatim. The permission baseline merges under
          it, so a `permission` key here replaces the baseline in full.
        '';
      };

      options.kdn.opencode.allowedPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/nix/store/**" ];
        example = [
          "/nix/store/**"
          "~/src/**"
        ];
        description = ''
          The path globs that a read-only tool reaches with no question. Each glob lands in the
          `external_directory`, `read`, `glob`, `grep` and `list` permission blocks as `allow`.

          The default names the store only. Add your own checkout root here.
        '';
      };

      options.kdn.opencode.authFile = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.local/share/opencode/auth.json";
        description = ''
          The file that `authKeys` reads. This is opencode's own credential store, so the default
          fits every installation. The value goes into a shell script, so a `$HOME` reference works.
        '';
      };

      options.kdn.opencode.authKeys = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          SOME_PROVIDER_API_KEY = "some-provider";
        };
        description = ''
          Environment variable name to provider id. The wrapper reads `.<provider>.key` from
          `authFile` and exports the value. An empty set exports nothing.
        '';
      };

      options.kdn.opencode.wrapper = lib.mkOption {
        type = lib.types.submodule {
          options.env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Literal `NAME=VALUE` exports that the wrapper sets before it execs.";
          };
          options.envFiles = lib.mkOption {
            type = lib.types.attrsOf lib.types.path;
            default = { };
            description = "Environment name to file path. The wrapper exports the file content.";
          };
          options.preExec = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra shell lines that the wrapper runs before it execs opencode.";
          };
        };
        default = { };
        description = ''
          Extensions to the single wrapper. Another aspect adds an environment variable or a step
          here, so no consumer needs a second wrapper of its own.
        '';
      };

      options.kdn.opencode.clankTalk = lib.mkOption {
        type = lib.types.submodule {
          options.enable = lib.mkEnableOption "the ClankTalk OpenCode plugin shim";

          options.package = lib.mkOption {
            type = lib.types.package;
            description = ''
              The `clank-talk` package that provides the OpenCode plugin folder. Set it from the
              flake output, because a devenv `pkgs` has no repository overlay.
            '';
          };
        };
        default = { };
        description = ''
          Generate a gated shim for ClankTalk's OpenCode V2 plugin. The shim loads the upstream
          plugin only when `KDN_CLANK_TALK=1`, so a normal OpenCode session does not get the
          `clank_talk` tool. Use `clank-opencode` to set the variable.
        '';
      };

      config = {
        opencode.enable = true;

        # `//` order matters. The baseline goes in first, so `cfg.settings.permission` replaces it.
        # `model` goes in last, and only when the consumer named one.
        opencode.settings = {
          permission = defaultPermission;
        }
        // cfg.settings
        // lib.optionalAttrs (cfg.defaultModel != null) { model = cfg.defaultModel; };

        packages = [ opencodeBin ];

        # A stable system prompt: replace the injected date with a pointer to the `current-date`
        # skill, so the prompt prefix does not change at midnight. opencode auto-loads everything
        # under `.opencode/plugins/`. The `current-date` skill is tracked repo content under
        # `.opencode/skills/`, not generated here.
        files.".opencode/plugins/kdn-opencode-stable-prompt.ts".text = stablePromptPlugin;

        # The ClankTalk shim is a plugin package directory. OpenCode 2.2.5 loads it only when its
        # files are regular files, so copy them from the store on each shell entry. Compare first
        # and replace atomically, so a live server never reads a half-written file.
        enterShell =
          lib.optionalString cfg.clankTalk.enable ''
            install -d .opencode/plugins/kdn-clank-talk
            for pair in "index.js:${clankTalkIndexFile}" "tui.js:${clankTalkTuiFile}" "package.json:${clankTalkPackageFile}"; do
              name="''${pair%%:*}"
              src="''${pair#*:}"
              dest=".opencode/plugins/kdn-clank-talk/$name"
              if ! cmp -s "$src" "$dest"; then
                install -m 0644 "$src" "$dest.tmp"
                mv "$dest.tmp" "$dest"
              fi
            done
          ''
          + lib.optionalString (!cfg.clankTalk.enable) ''
            rm -rf .opencode/plugins/kdn-clank-talk
          '';

        # The aspect's own smoke test. It stays offline: the sandbox has no network and no real
        # `$HOME`, so nothing here starts opencode itself.
        enterTest = ''
          echo "• opencode: the binary on PATH is the wrapper" >&2
          test -x "$(command -v opencode)"
          grep -q 'KDN_OPENCODE_WRAPPER=1' "$(command -v opencode)"

          echo "• opencode: the wrapper execs a store path" >&2
          grep -qE '^exec /nix/store/' "$(command -v opencode)"

          ${lib.optionalString cfg.clankTalk.enable ''
            echo "• opencode: the ClankTalk shim is a regular file" >&2
            test -f .opencode/plugins/kdn-clank-talk/index.js
            test ! -L .opencode/plugins/kdn-clank-talk/index.js
            test ! -L .opencode/plugins/kdn-clank-talk/tui.js
            test -f .opencode/plugins/kdn-clank-talk/package.json
            grep -q 'KDN_CLANK_TALK' .opencode/plugins/kdn-clank-talk/index.js
            grep -q 'KDN_CLANK_TALK' .opencode/plugins/kdn-clank-talk/tui.js
          ''}
        '';
      };
    };
}
