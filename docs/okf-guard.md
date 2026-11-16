---
type: Reference
description: The content-safety scanner for OKF pipelines — hidden content and prompt-injection patterns, the intake procedure, exit codes, supported formats and the memory-bundle gate.
timestamp: 2026-11-16T16:05:00+01:00
---

# `okf-guard`

[`okf-guard`](https://github.com/darshanNhb/okf-guard) screens a raw source document before its
text enters a trusted knowledge bundle. It is the intake gate for `.agents/knowledge`: a file that
carries invisible instructions must not become a concept.

The packaged version is **v0.1.0**, pre-1.0 and alpha. Treat the scanner as one layer, not as proof
that a document is safe.

## What it detects

Hidden content, per format:

| Format                | Signals                                                       |
| --------------------- | ------------------------------------------------------------- |
| `.txt`, `.md`, `.csv` | injection patterns, zero-width and control characters         |
| `.html`, `.htm`       | hidden elements, `display:none`, comments, injection patterns |
| `.docx`               | `font.hidden`, white-on-white text, matching shading          |
| `.pptx`               | hidden slides and runs, white-on-white text                   |
| `.xlsx`               | hidden rows/columns/sheets, white font on white fill          |

Prompt injection: instruction override, fake system markers, fake role assertion, data
exfiltration and related pattern families.

## Supported formats

Text, HTML, Word, PowerPoint, spreadsheets and PDF all work. The PDF adapter reads
`pdfplumber`, which nixpkgs builds with `doCheck = false`: its test inputs pull pandas, jupyterlab
and geopandas, and geopandas 1.1.4 fails 10 of its own tests against the newer pyarrow and shapely.
None of those is a runtime dependency, so the override keeps the adapter without a broken test
dependency in the closure.

## Exit codes

| Code | Meaning    | What to do                                                                         |
| ---- | ---------- | ---------------------------------------------------------------------------------- |
| 0    | pass       | The text may enter the bundle.                                                     |
| 1    | quarantine | A human reviews the flags before the text enters.                                  |
| 2    | block      | Do not ingest the text.                                                            |
| 3    | error      | A missing parser, an unreadable file or a crash. Fix the cause; never assume pass. |

## Intake procedure

```sh
# A single external document.
okfguard scan ./incoming/report.docx

# A directory of sources; only supported extensions are read.
okfguard scan ./incoming --recursive

# Machine-readable output, one JSON object per line. Keep it for the review step.
okfguard scan ./incoming --recursive --json > /tmp/okfguard.jsonl

# Triage quarantined entries interactively.
okfguard review --json-log /tmp/okfguard.jsonl
```

Only the `clean_text` of a passing document is quoted into a concept. Do not copy the raw file into
the bundle, and do not paste a flagged snippet "for context": the pattern is the payload.

`review` is a triage aid. It prints each quarantined item and records a decision in the terminal; it
does not edit the bundle.

## Where the gate runs

- **On intake.** The rule in [`.agents/rules/okf-memory.md`](../.agents/rules/okf-memory.md) makes
  the scan a condition of quoting an external document into `.agents/knowledge`.
- **On the bundle.** `okf-guard-test` scans `.agents/knowledge --recursive` and fails on any
  non-zero exit. The bundle is small and curated, so the gate stays quiet; it catches text that
  arrived without the intake step.
- **Not on the repository's own docs.** `docs/` quotes injection strings on purpose. A full scan
  reports 44 quarantines and 3 blocks, so a `docs/` gate would be noise, not safety.

## Check

`checks/default.nix` builds `okf-guard-test`: a clean file must exit 0, a known injection must exit
2, a PDF with white-on-white text must exit 2, and the memory bundle must exit 0. The check proves
the packaged scanner still detects what it claims to detect; a silent regression in the package
would otherwise pass unnoticed.

## Relationship to the other tools

| Tool               | Owns                                      |
| ------------------ | ----------------------------------------- |
| `okf-guard`        | screening a source document before intake |
| `okf-agent-memory` | writing the memory bundle                 |
| `ai-xf-validate`   | the AI-XF Level 2 structure of the bundle |
| `kdn-okf`          | reading the bundle                        |

`okf-guard` and `okf-agent-memory` answer different questions. The scanner asks "is this text
hostile?"; the memory tool asks "is this concept well-formed and current?". Neither replaces the
other.
