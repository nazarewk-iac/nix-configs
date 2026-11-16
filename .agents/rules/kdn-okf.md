---
type: Rule
description: "Read an OKF v0.2 bundle in slices with kdn-okf, gate it with okf-rs/okflint/okph, and move concepts only with okf-rs mv."
timestamp: 2026-11-16T14:30:00+01:00
---

# Reading an OKF bundle with `kdn-okf`

Full doc: [docs/kdn-okf.md](../../docs/kdn-okf.md). The tool lives in
[`packages/kdn-okf/`](../../packages/kdn-okf/).

- **Orient with the index, not with `cat`.** `kdn-okf list --json`, `types`, `tags`, `statuses`,
  `trust`. Add `--stale`, `--orphan`, `--broken` or `--unverified` to narrow.
- **Read in slices.** `outline` gives the heading tree with 1-based line ranges; `section` returns
  exactly one range; `context` fits a line budget. Do not load a whole large concept when one
  section answers the question.
- **Use `--jsonl` for streams.** One JSON object per line, no envelope: `list`, `search`, facets,
  `links`, `backlinks` and `doctor` are the line-oriented commands. Use `--json` when you need the
  envelope and its `issues` array.
- **`doctor --parse-only` is the gate.** Exit 0 when every concept has frontmatter and a non-empty
  `type`; a broken link, a missing backlink, an orphan or an absent optional family is a warning
  and never fails the gate. `--ignore <code>` drops a known finding.
- **The browser is read-only by default.** The one writer is `kdn-okf generate-index`, which is
  explicit, deterministic, marked as generated and refuses a human-authored `index.md` unless
  `--force`. `--print-path` composes with `$EDITOR`; `show --raw` is byte-identical to the file.
- **Selectors are exact by default.** A prefix needs `--prefix`; an ambiguous selector exits 2 and
  lists candidates on stderr, so `$(kdn-okf show x --print-path)` never captures a menu.
- **Trust and freshness are derived, not asserted.** `unverified` is the absence of `verified`;
  `stale` compares `stale_after` against `--now` or the clock.
- **Move and delete only with `okf-rs`.** `okf-rs mv <old> <new> --bundle <bundle>` rewrites every
  incoming link, rebases outgoing links and keeps the AI-XF `id`; `okf-rs rm` refuses a concept
  that still has incoming links unless `--redirect-to` or `--unlink` says what to do. Never move a
  concept by hand, and never delete one without `okf-rs rm`.
- **The external gates are `okf-rs validate`, `okf-rs lint` and `okf-rs links --broken --check`;
  `okflint validate --manifest <bundle>/okf-base.yaml <bundle>`; and
  `okph validate <bundle> --strict --ignore prefer-absolute-links`.** `doctor` stays the fast
  in-process check and does not shell out. Full doc: [docs/okf-toolchain.md](../../docs/okf-toolchain.md).
- **Before a review, ask what the change touches.**
  `okph affected --git <base> --root .agents/knowledge` lists the changed concepts and everything
  that cites them, transitively.
