---
type: Reference
description: The external OKF tools — okf-rs for strict conformance, lint, links and link-safe refactors; okflint for the per-type manifest gate; okph for graph and impact analysis.
timestamp: 2026-11-16T16:30:00+01:00
---

# The OKF toolchain

Three pinned tools sit around the memory bundle. Each answers a different question:

| Tool      | Question                                                                                              | Gate                                         |
| --------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `okf-rs`  | Is the bundle strictly OKF v0.2, does it lint clean, and can I move a concept without breaking links? | `validate`, `lint`, `links --broken --check` |
| `okflint` | Does every concept match the declared type profile?                                                   | `validate --manifest`                        |
| `okph`    | What links to this concept, and what does a branch touch?                                             | `validate --strict`                          |

`kdn-okf doctor` stays the fast, in-process structural check. It does not shell out to these tools:
`doctor` must run with no external binary, and its issue codes are its own. Run the external gates
next to it.

## `okf-rs`

The pure-Rust OKF toolkit from [W4G1/okf](https://github.com/W4G1/okf). The package installs the
binary as **`okf-rs`**; upstream calls it `okf`, which reads like the format itself.

```sh
okf-rs validate .agents/knowledge          # strict OKF v0.2 conformance
okf-rs lint .agents/knowledge              # 13 hygiene rules; warnings fail
okf-rs links .agents/knowledge --broken --check
okf-rs trust .agents/knowledge             # trust tiers and staleness
okf-rs graph .agents/knowledge --format mermaid
okf-rs diff ./bundle-a ./bundle-b          # semantic diff
```

### Refactoring without broken links

This is the capability the repository lacked. Never move or delete a concept by hand:

```sh
okf-rs mv decisions/old-name decisions/new-name --bundle .agents/knowledge
okf-rs mv --dry-run --json decisions/old-name decisions/new-name --bundle .agents/knowledge
okf-rs rm decisions/old-name --redirect-to decisions/new-name
okf-rs rm decisions/old-name --unlink
```

`mv` rewrites every incoming link, rebases outgoing relative links and keeps the AI-XF `id`. The
body mirror that AI-XF Level 2 requires is rewritten too, so `ai-xf-validate --level 2` still
passes. `rm` refuses when a link points at the concept unless `--redirect-to` or `--unlink` says
what to do with that link.

### What lint reports

`lint` exits non-zero on warnings. The seed is clean. Two findings remain and are **informational
only**:

- `L2` frontmatter keys are not in canonical order. `okf fmt` would reorder them, but
  `okf-memory update` writes its own order, so the finding returns on the next update.
- `L11` no `verified` events. That is the honest state until a human verifies a concept.

## `okflint`

A deterministic compliance linter with a manifest that declares the standard. The manifest for the
memory bundle is `.agents/knowledge/okf-base.yaml`; it requires `type`, `title`, `description`,
`status` and `generated`, and constrains `status` to `draft`, `stable` or `deprecated`.

```sh
okflint validate-manifest .agents/knowledge/okf-base.yaml
okflint validate --manifest .agents/knowledge/okf-base.yaml .agents/knowledge
okflint audit --manifest .agents/knowledge/okf-base.yaml .agents/knowledge --json
```

`validate` exits 0 when conformant and 1 otherwise; `validate-manifest` exits 0 or 2. `audit`
always exits 0 and reports statistics, broken links and split candidates.

Do not use `okflint index`: `okf-agent-memory` owns `index.md` and `log.md`.

## `okph`

Graph and impact analysis from [Fcmam5/okph](https://github.com/Fcmam5/okph). It treats a link as a
citation: `a → b` means "a relies on b", so `affected b.md` lists `b.md` and everything that cites
it, transitively.

```sh
okph validate .agents/knowledge --strict --ignore prefer-absolute-links
okph deps decisions/path-scoped-jj.md
okph dependents decisions/path-scoped-jj.md
okph affected --git origin/main --root .agents/knowledge
okph affected --git origin/main --root .agents/knowledge --md
okph graph .agents/knowledge --base-url https://example.com/knowledge
```

`deps`, `dependents` and `affected` read from the current directory; run them from
`.agents/knowledge`, or pass `--root`.

`prefer-absolute-links` is ignored in the gate. The OKF spec only _recommends_ the absolute form,
and the bundle uses relative links because `okf-memory relate` and the AI-XF body mirrors write
them. Ignoring the warning keeps `--strict` meaningful for the checks that matter.

## Which gate runs when

| Change                           | Run                                                   |
| -------------------------------- | ----------------------------------------------------- |
| Edit a concept body              | `okf-rs validate`, `okf-rs lint`, `okflint validate`  |
| Add or remove a concept          | the same, plus `okph validate --strict`               |
| Move, rename or delete a concept | `okf-rs mv` / `okf-rs rm`, then every gate            |
| Before a review or a push        | `okph affected --git <base> --root .agents/knowledge` |

The checks `okf-rs-check`, `okflint-validate` and `okph-validate` run the three gates on the memory
bundle in the Nix sandbox.
