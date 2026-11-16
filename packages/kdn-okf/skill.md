---
name: kdn-okf
description: Index, search and browse an Open Knowledge Format v0.2 bundle — list concepts by type, tag, status and trust, read outline/section/context slices, follow links and backlinks, and validate with doctor.
---

# kdn-okf

Use this skill when a repository or directory is an OKF v0.2 bundle: Markdown files with YAML
frontmatter, `type` required, `index.md` and `log.md` reserved.

## Orient

```sh
kdn-okf index --json
kdn-okf types --json
kdn-okf tags --json
kdn-okf list --json
kdn-okf list --status draft --json
kdn-okf list --stale --json
kdn-okf doctor --parse-only --json
```

Every read command has `--json`. Use it; the text output is for people. `--bundle <dir>` selects a
bundle explicitly; otherwise the tool walks up to the nearest `index.md`.

## Read progressively, not whole files

```sh
kdn-okf outline <concept> --depth 2 --json
kdn-okf section <concept> <heading> --json
kdn-okf context <concept> --budget 80 --json
kdn-okf search <query> --scope body --json
```

`outline` gives the heading tree with 1-based line ranges; `section` returns exactly one range;
`context` fits a line budget. Load the slice you need, not the whole body.

## Follow the graph

```sh
kdn-okf links <concept> --json
kdn-okf backlinks <concept> --json
kdn-okf orphans --json
kdn-okf broken --json
kdn-okf graph --format dot
```

`links` lists outgoing links with `kind` (`bundle-absolute`, `relative`, `external`, `fragment`)
and `missing`; `backlinks` lists incoming links. A broken link is a warning, never a parse failure.

## Trust and freshness

- `trust` is `unverified`, `machine-confirmed` or `human-reviewed`, derived from `verified`.
- `stale` is true when `stale_after` is in the past.
- `--now <RFC3339>` pins the clock for reproducible output.

## Rules

- The browser is read-only. It never writes into the bundle.
- `doctor --parse-only` is the gate: exit 0 when every concept has frontmatter and a non-empty
  `type`; broken links and missing optional fields do not fail it.
- Prefer `--json` and one `jq` expression over parsing the text tables.
- `kdn-okf open <concept> --print-path` composes with `$EDITOR`; `show --raw` is byte-identical to
  the file.
