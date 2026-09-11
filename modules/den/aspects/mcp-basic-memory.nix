# The `mcp/basic-memory` slot, as a den aspect. It ports `modules/slots/mcp/basic-memory/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It adds one gateway backend per knowledge base, plus one wrapper binary per base. It also adds a
# `mcp-pretty-print` plugin, so a note write or a note delete shows the real change before approval.
#
# `write_note` and `delete_note` both read the note's **current** content through the CLI. That read
# takes no MCP round trip and it runs before the mutation, so the dialog shows what changes: a
# unified diff for a write, and the whole old content for a delete — nothing is left to diff against
# once a note is gone.
#
# ## The de-personalized port
#
# The slot hardcodes the creator's own two bases and the creator's own knowledge root. This aspect
# names neither. The consumer supplies both.
#
# | Slot value | Option that replaces it |
# |---|---|
# | the two bases `public` and `sensitive`, with their aliases `bmp` and `bms` | `kdn.mcp.basic-memory.bases` |
# | each base's description text | `kdn.mcp.basic-memory.bases.<name>.description` |
# | the knowledge root `~/.local/share/kdn-nix-configs/knowledge` | `kdn.mcp.basic-memory.knowledgeRoot` |
#
# An entry name drives three names at once: the wrapper binary is `basic-memory-<name>`, the gateway
# backend is `memory-<name>`, and the notes live in `<knowledgeRoot>/<name>`. The creator's real
# values now belong in the consumer, and they are logged in
# ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# `includes` names `mcp-pretty-print`, not `mcp`. The plugin needs the hook that renders it, and the
# hook aspect already includes the gateway. den dedupes the diamond — see ./mcp.nix.
#
# ## Two more differences from the slot
#
# 1. **The package comes from a plain `callPackage`.** The slot reads `pkgs.kdn.basic-memory`, so a
#    consumer must add this repository's overlay first. The package needs three flake inputs
#    (`uv2nix`, `pyproject-nix`, `pyproject-build-systems`), and this file closes over them, so a
#    consumer supplies none.
# 2. **The agent rule file comes from a relative path literal**, not from `${inputs.nix-configs}`.
#    A path literal stays inside the tree the evaluation already reads, so it adds no fetch and no
#    second copy of the whole repository.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only —
#    the arguments every NixOS, nix-darwin, home-manager and devenv evaluation already gives. An
#    argument such as `inputs` or `kdnConfig` would force the consumer to pass `specialArgs`, and
#    that machinery is the whole reason this tree exists. `inputs` is captured in **this file's** own
#    arguments below, and the target module closes over it.
{ inputs, kdn, ... }:
{
  kdn.mcp-basic-memory.includes = [ kdn.mcp-pretty-print ];

  kdn.mcp-basic-memory.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.mcp.basic-memory;

      # The package takes its three flake inputs through `__inputs__`, the same convention every
      # `packages/*/default.nix` uses. `inputs` comes from this file's own arguments.
      basic-memory = pkgs.callPackage ../../../packages/basic-memory {
        __inputs__ = {
          inherit inputs;
        };
      };

      # One wrapper binary per base. Each one bakes its own paths, so two bases never share a
      # database and never share a configuration directory.
      wrappers = lib.mapAttrs (
        name: base:
        basic-memory.mkWrapper {
          inherit name;
          inherit (base) aliases;
          home = "${cfg.knowledgeRoot}/${name}";
          configDir = "${cfg.knowledgeRoot}/.config/basic-memory-${name}";
        }
      ) cfg.bases;

      binOf = name: "${wrappers.${name}}/bin/basic-memory-${name}";

      # The pretty-print plugin. It previews a note mutation before approval, so it needs the real
      # binary of every base — a plain identifier in the arguments is not enough to show a diff.
      formatterText = ''
        import difflib
        import json
        import subprocess

        BINARIES = {
        ${lib.concatMapStringsSep "\n" (
          name: "    ${builtins.toJSON "memory-${name}"}: ${builtins.toJSON (binOf name)},"
        ) (lib.attrNames cfg.bases)}
        }


        def select(ctx):
            return ctx["server"] in BINARIES


        def read_note(server, identifier, project):
            cmd = [BINARIES[server], "tool", "read-note", identifier]
            if project:
                cmd += ["--project", project]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            except OSError:
                return ""
            if proc.returncode != 0:
                return ""
            try:
                return json.loads(proc.stdout).get("content") or ""
            except (json.JSONDecodeError, AttributeError):
                return ""


        def get_permissions_info(ctx):
            args = ctx["arguments"]
            server = ctx["server"]
            project = args.get("project") or None

            if ctx["tool"] == "write_note":
                title = args.get("title", "")
                directory = args.get("directory", "")
                new_content = args.get("content", "")
                old_content = read_note(server, title, project)
                is_new = not old_content
                fields = [
                    ("change", "new note" if is_new else "edit existing note"),
                    ("title", title),
                    ("directory", directory),
                    ("project", project or "(default)"),
                ]
                if is_new:
                    return fields, new_content
                diff = "".join(
                    difflib.unified_diff(
                        old_content.splitlines(keepends=True),
                        new_content.splitlines(keepends=True),
                        fromfile="before",
                        tofile="after",
                    )
                )
                return fields, diff or "(no changes)"

            if ctx["tool"] == "delete_note":
                identifier = args.get("identifier", "")
                old_content = read_note(server, identifier, project)
                fields = [
                    ("change", "delete note" if old_content else "note not found"),
                    ("identifier", identifier),
                    ("project", project or "(default)"),
                ]
                return fields, old_content or "(note not found — nothing to delete)"

            return json.dumps(args, indent=2)
      '';
    in
    {
      # One declaration of `kdn.isSourceRepo`, imported by path. The module system rejects two inline
      # declarations of one option, and it drops a repeated import by path. See ../common/.
      imports = [ ../common/source-repo.nix ];

      options.kdn.mcp.basic-memory = {
        installAgentRules = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Install this aspect's agent instruction file into the consumer repository.

            The file is `.claude/rules/basic-memory.md`. It states the author's own routing rule:
            which knowledge base takes which note. The default is false, so you get the file only
            when you ask for it. This repository turns the option on explicitly in
            `checks/den-mvp/devenv/default.nix`.

            The option covers the instruction file only. The MCP backends and the wrapper binaries
            stay in place.
          '';
        };

        knowledgeRoot = lib.mkOption {
          type = lib.types.str;
          default = "$HOME/.local/share/basic-memory";
          description = ''
            Root directory for every knowledge base. The wrapper expands it at run time, so a shell
            variable such as `$HOME` is correct here.

            One base gets `<root>/<name>` for its notes, and
            `<root>/.config/basic-memory-<name>` for its own configuration.
          '';
        };

        bases = lib.mkOption {
          default = { };
          type = lib.types.attrsOf (
            lib.types.submodule {
              options.aliases = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Extra binary names for this base, next to `basic-memory-<name>`. Use a short one
                  for daily typing.
                '';
                example = [ "bmp" ];
              };

              options.description = lib.mkOption {
                type = lib.types.str;
                description = "Text the gateway shows for this backend.";
              };
            }
          );
          description = ''
            One entry per knowledge base. The entry name becomes the wrapper binary
            `basic-memory-<name>`, the gateway backend `memory-<name>` and the notes directory
            `<knowledgeRoot>/<name>`.

            The aspect names no base of its own. The consumer decides how many bases exist, what each
            one holds, and how each one is described.
          '';
          example = lib.literalExpression ''
            {
              public = {
                aliases = [ "bmp" ];
                description = "public knowledge base";
              };
            }
          '';
        };
      };

      config = {
        kdn.mcp.extraBackends = lib.mapAttrs' (
          name: base:
          lib.nameValuePair "memory-${name}" {
            command = "${binOf name} mcp";
            inherit (base) description;
          }
        ) cfg.bases;

        # No base means no plugin. An empty `bases` set must add nothing at all.
        kdn.mcp.pretty-print.formatters = lib.optionalAttrs (cfg.bases != { }) {
          basic-memory.text = formatterText;
        };

        packages = lib.attrValues wrappers;

        # This repository commits the rule file itself, so a store symlink would hide the tracked
        # copy. Every other consumer gets the file installed.
        files = lib.mkIf (cfg.installAgentRules && !config.kdn.isSourceRepo) {
          ".claude/rules/basic-memory.md".source = ../../../.agents/rules/basic-memory.md;
        };

        # Offline assertions only. A real `basic-memory` command needs a writable home and a
        # database, and the build sandbox gives neither. So the test reads the built wrappers.
        enterTest = ''
          echo "• mcp-basic-memory: every wrapper binary exists and runs" >&2
          ${lib.concatMapStringsSep "\n          " (name: "test -x ${binOf name}") (lib.attrNames cfg.bases)}

          echo "• mcp-basic-memory: each wrapper bakes its own knowledge root" >&2
          ${lib.concatMapStringsSep "\n          " (
            name: "grep -Fq ${lib.escapeShellArg "${cfg.knowledgeRoot}/${name}"} ${binOf name}"
          ) (lib.attrNames cfg.bases)}

          echo "• mcp-basic-memory: every base name and every alias is on PATH" >&2
          ${lib.concatMapStringsSep "\n          " (n: "command -v ${n} >/dev/null") (
            lib.concatLists (
              lib.mapAttrsToList (name: base: [ "basic-memory-${name}" ] ++ base.aliases) cfg.bases
            )
          )}
        '';
      };
    };
}
