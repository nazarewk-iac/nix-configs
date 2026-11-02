# The repository formatter. `nix fmt` runs it, `nix flake check` runs it in check mode, and
# `jj fix` runs the same tools on every snapshot (see `kdn.jj.config.fix` in devenv.nix).
#
# ## Why treefmt
#
# The tree is six languages, and each needs its own tool. treefmt runs one program per file type and
# exposes a single `formatter.${system}` output, so one command covers everything without a shell
# script of `fd` + `xargs`. It also guards the seams: a file matches at most one formatter, so two
# tools never fight over the same bytes.
#
# ## One tool per language
#
# | Language | Tool          | Why this one                                                  |
# | -------- | ------------- | ------------------------------------------------------------- |
# | Nix      | nixfmt        | The tree is already nixfmt-clean; `kdn-nix-fmt` used the same. |
# | Markdown | prettier      | Pads table cells so the pipes line up.                        |
# | Python   | ruff format   | The tree is already ruff-formatted. A formatter, not a linter. |
# | Go       | gofumpt       | A stricter gofmt; the tree is already gofumpt-clean.          |
# | Shell    | shfmt         | Two-space indent, no `simplify`; matches the existing style.  |
# | TOML     | taplo         | Sorts nothing by default; only normalises layout.             |
# | JSON     | prettier      | Same tool as Markdown; JSON is a prettier preset.             |
# | YAML     | yamlfmt       | Keeps block style; does not fold long strings.                |
#
# `ruff-format` is the formatter half of ruff. The linter half (`ruff check`) is not run here: a
# formatter must not change meaning, and a lint fix can.
{ ... }:
{
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true;

    prettier = {
      enable = true;
      includes = [
        "*.md"
        "*.mdx"
        "*.json"
      ];
      settings = {
        proseWrap = "preserve"; # keep the author's line breaks in prose
        printWidth = 100;
      };
    };

    ruff-format.enable = true;

    # `gofumpt` and not `gofmt`: it is gofmt plus a few stricter rules, and the Go files here are
    # already gofumpt-clean. It is a superset, so a gofmt-clean file stays clean.
    gofumpt.enable = true;

    # Two-space indent, no `-s`: `simplify` can rewrite a construct that the author wrote on
    # purpose, and the formatter must not change meaning.
    shfmt = {
      enable = true;
      indent_size = 2;
      simplify = false;
    };

    # taplo sorts nothing unless told to, so `taplo format` only normalises layout. Key order is
    # part of a file's meaning here (a flake input block reads top to bottom), so no sorting.
    taplo.enable = true;

    yamlfmt.enable = true;
  };

  # Do not reformat files that are generated, vendored, or whose layout carries meaning.
  settings.excludes = [
    # Lock files are machine-written; a reformat is churn with no reader.
    "*.lock"
    "*.lock.md"
    "devenv.lock"
    "flake.lock"
    "package-lock.json"
    "go.sum"

    # A SOPS file carries an encrypted `sops:` block whose layout is part of the ciphertext
    # envelope. Reformatting it breaks decryption.
    "*.sops.yaml"

    # The unattended-install secret mirrors its own SOPS layout for the same reason.
    "default.unattended.sops.yaml"

    # This template is copied verbatim by `init-py-script`. Its placeholders and its layout are the
    # product, so a formatter must not touch it.
    "packages/init-py-script/template/**"

    # Generated build inputs and tool state.
    "node_modules/**"
    ".devenv/**"
    ".jj/**"
  ];
}
