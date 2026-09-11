{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.kdn.mcp.basic-memory;
  # One wrapper per knowledge base. `knowledgeRoot` states where the notes live, so the
  # package's own default path never applies and no repository name reaches the store.
  mkBase =
    name: aliases:
    pkgs.kdn.basic-memory.mkWrapper {
      inherit name aliases;
      home = "${cfg.knowledgeRoot}/${name}";
      configDir = "${cfg.knowledgeRoot}/.config/basic-memory-${name}";
    };
  bmp = mkBase "public" [ "bmp" ];
  bms = mkBase "sensitive" [ "bms" ];
in
{
  options.kdn.mcp.basic-memory = {
    enable = lib.mkEnableOption "basic-memory knowledge base MCP backends";

    installAgentRules = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install this slot's agent instruction file into the consumer repository.

        The file is `.claude/rules/basic-memory.md`. It states the author's own routing rule: which
        knowledge base takes which note. The default is false, so you get the file only when you ask
        for it. This repository turns the option on explicitly in its own `devenv.nix`.

        The option covers the instruction file only. The MCP backends and the wrapper binaries stay
        in place.
      '';
    };

    knowledgeRoot = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/basic-memory";
      description = ''
        Root directory for every knowledge base. The wrapper expands it at run time,
        so a shell variable such as `$HOME` is correct here.

        One base gets `<root>/<name>` for its notes, and
        `<root>/.config/basic-memory-<name>` for its own configuration.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.mcp.extraBackends = {
      memory-public = {
        command = "${bmp}/bin/basic-memory-public mcp";
        description = "basic-memory public knowledge base (open-source tooling, public knowledge)";
      };
      memory-sensitive = {
        command = "${bms}/bin/basic-memory-sensitive mcp";
        description = "basic-memory sensitive knowledge base (private, internal)";
      };
    };

    # basic-memory calls carry markdown note content (write_note) or plain identifiers
    # (delete_note, read_content, ...) as arguments — preview those directly, before approval,
    # instead of the generic JSON-arguments dump the pretty-print hook falls back to.
    # kdn.mcp.pretty-print's PermissionRequest hook (modules/slots/mcp/pretty-print/) replaces
    # Claude Code's own approval dialog outright with a readable one built from this plugin.
    #
    # write_note/delete_note both read the note's *current* content via the CLI (no MCP
    # round-trip, and it runs synchronously before the mutation) so the dialog body can show
    # what's actually changing: a unified diff for write_note, the full old content for
    # delete_note (nothing to diff against once it's gone).
    kdn.mcp.pretty-print.formatters.basic-memory.text = ''
      import difflib
      import json
      import subprocess

      BINARIES = {
          "memory-public": "${bmp}/bin/basic-memory-public",
          "memory-sensitive": "${bms}/bin/basic-memory-sensitive",
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

    devenv = {
      packages = [
        bmp
        bms
      ];

      files = lib.mkIf (cfg.installAgentRules && !config.kdn.isSourceRepo) {
        ".claude/rules/basic-memory.md".source = "${inputs.nix-configs}/.agents/rules/basic-memory.md";
      };
    };
  };
}
