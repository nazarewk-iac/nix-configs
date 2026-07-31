---
type: Rule
description: Requires strict ASD-STE100 (Simple Technical English) for all docs, code comments, and chat, with a domain-vocabulary exception and an ask-the-user escape hatch.
timestamp: 2026-07-31T14:00:00+02:00
---

# Simple Technical English (ASD-STE100)

Write all new or substantially edited text in strict ASD-STE100 Simple Technical English. This
covers Markdown docs (tasks, skills, `.agents/rules/`, `docs/`), **code comments and
docstrings** (shell, Nix, Python, and any other language), commit messages, and chat replies.

## Grammar and style rules

Apply the full STE rules:

- Keep sentences short — at most 20 words for an instruction, at most 25 for a description.
- Write one instruction per sentence.
- Use the active voice.
- Use the present tense.
- Use consistent terminology. Do not use a synonym for a term you already used.
- Do NOT use `-ing` forms (gerunds and participles), except inside a technical name.
- Cut filler. Keep the technical fact.

## Domain vocabulary exception

Keep real technical terms that name actual concepts, even when STE does not approve them. Do not
paraphrase them away — they are the correct precise words. Examples from this repo's domain:

- `viewport`, `scrollback`, `idempotent`, `delimiter`, `snapshot`
- tool and protocol names: `zellij`, `jj`, `devenv`, `flake`, `derivation`, `NixOS`
- established compounds: `long-running`, `naming convention`

Treat this as a per-domain allowlist, not a blanket exception. When a plain STE word says the
same thing, use the plain word.

## Escape hatch

When you feel strongly that STE is wrong for a specific use case, do NOT silently drop it. Ask
the user for a decision first. State the case and the reason, then wait. For example: a verbatim
error message, a quoted upstream text, or a legal notice may need its original wording.
