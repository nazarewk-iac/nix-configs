---
type: Research
description: What projects actually put in Co-authored-by and Assisted-by trailers for AI agents, why several major projects reject Co-authored-by for AI, and how jj constrains per-change metadata.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T09:10:00+01:00
---

# Research: AI commit attribution and jj metadata

## 1. What agents put in `Co-authored-by`

Several agent harnesses append a `Co-authored-by` trailer by default:

| Agent                | Common trailer                                           | Notes                                                                          |
| -------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Claude Code          | `Co-authored-by: Claude <noreply@anthropic.com>`         | On by default; configurable with `includeCoAuthoredBy` / `attribution.commit`. |
| Codex                | `Co-authored-by: Codex <noreply@openai.com>`             | Workspace policy controls it; GitHub has a Codex account.                      |
| GitHub Copilot (IDE) | `Co-authored-by: Copilot <copilot@github.com>`           | VS Code `git.addAICoAuthor`; default often `chatAndAgent`.                     |
| Copilot SWE agent    | `Co-authored-by: Copilot <...@users.noreply.github.com>` | Fixed bot identity; shows as a bot contributor.                                |
| Cursor               | `Co-authored-by: Cursor <cursoragent@cursor.com>`        | IDE default; CLI/cloud less controllable.                                      |

GitHub renders these as extra avatars and, when the email maps to a GitHub account, counts them in
contribution stats. That is the main reason agents use it. It is a **GitHub-specific credit
mechanism**, not a neutral disclosure format.

The human is already the commit author. Adding the human to `Co-authored-by` is redundant and does
not disclose AI use. If a project insists on the GitHub avatar convention, the co-author should be
the **agent identity**, never the human author.

## 2. Why many projects reject `Co-authored-by` for AI

Serious AI policies increasingly say the opposite: do not use `Co-authored-by` for a model, because
it implies human co-authorship and can carry DCO implications. Use a dedicated disclosure trailer.

| Project          | Required/expected trailer                        | Position on `Co-authored-by`                                              |
| ---------------- | ------------------------------------------------ | ------------------------------------------------------------------------- |
| Nixpkgs          | `Assisted-by:` with tool + primary model/version | Explicitly says `Co-authored-by:` does **not** satisfy the policy.        |
| OpenInfra / Nova | `Assisted-By:` or `Generated-By:`                | “Do not use `Co-Authored-By:` for AI tools… it misrepresents authorship.” |
| LocalAI          | `Assisted-by: AGENT:MODEL [TOOLS]`               | AI must not add `Co-Authored-By` for itself.                              |
| Flux             | `Assisted-by: <agent>/<model>`                   | Do not use `Co-authored-by`; the co-author convention is for humans.      |
| Linux kernel     | `Assisted-by:` (being deprecated in 2026)        | AI must never add `Signed-off-by`; human remains accountable.             |
| Fedora / Rocky   | `Assisted-by:`                                   | Contributor remains the author and is accountable.                        |

The common shape is:

```
Assisted-by: <tool>:<model>
```

Examples from real policies:

```
Assisted-by: Copilot:claude-opus-4.6
Assisted-by: Claude:Opus-4.5
Assisted-by: my-agent my-model-v1
Generated-By: GitHub Copilot 0.37.6
Model: claude-opus-4-6-20250219
```

Some projects use `Generated-By` when the output is mostly machine-authored; `Assisted-By` when a
human materially revised it. Multiple tools may each get their own line. The human’s `Signed-off-by`
stays human-only.

## 3. Nixpkgs transparency policy

From `CONTRIBUTING.md` § Transparency:

- All covered LLM use must be disclosed.
- For commits, the disclosure **must** be an `Assisted-by:` Git commit trailer.
- The trailer includes at least the tool name and the primary model name and version.
- `Co-authored-by:` does **not** satisfy the policy.
- Pull request summaries and review comments are disclosed separately.

So the tool’s default must be `Assisted-by:`, not `Co-authored-by:`. A `Co-authored-by:` line can be
added for a project that wants the GitHub avatar convention, but it is not the compliance trailer.

## 4. Multi-field coverage

The conventions overlap but are not interchangeable. A tool can cover them with profiles:

| Field            | Consumers                                 | Semantics                                    | Default?                 |
| ---------------- | ----------------------------------------- | -------------------------------------------- | ------------------------ |
| `Assisted-by`    | Nixpkgs, OpenInfra, LocalAI, Flux, Fedora | AI materially assisted; human remains author | yes                      |
| `Session-Id`     | this repository's journal                 | local session key                            | yes                      |
| `Harness`        | this repository's tooling                 | machine-readable tool name                   | yes                      |
| `Model`          | this repository's tooling                 | machine-readable model/version               | yes                      |
| `Co-authored-by` | GitHub avatars/contributor graph          | a co-author, not a disclosure                | no; `github` profile     |
| `Generated-by`   | ASF, some projects                        | mostly machine-authored                      | no; `asf`/`full` profile |
| `Signed-off-by`  | DCO projects                              | human certification                          | never                    |

Why not write every field by default:

- `Generated-by` and `Assisted-by` are not synonyms. Writing both when a human revised the work
  overstates machine authorship.
- `Co-authored-by` implies co-authorship. Many projects reject it for AI; writing it by default can
  misrepresent the change and annoy maintainers.
- Extra trailers are noise in every `git log`, `jj log` and PR view. Profiles keep the default clean
  and let a project opt into the coverage it needs.
- The human author is already the author. The human must never appear in `Co-authored-by` just
  because an agent helped; the agent identity belongs there if the project uses that convention.

`Harness` and `Model` are redundant with `Assisted-by` for a human, but they let a parser read the
values without splitting a combined string. They are cheap and single-valued.

## 5. jj metadata limits

- `jj metaedit` can change the description, author, committer, timestamps and change ID. It has no
  arbitrary key/value metadata.
- The operation log records operations with a description, user, host and timestamps, but it is
  repo-global and has no public command to attach a custom session ID to a specific change.
- `jj` has no commit-msg hook; enforcement must be a wrapper command or a CI/doctor gate.
- A commit trailer in the description is the portable, Git-compatible channel. It survives clones
  and is readable by `jj log -T 'description'` and `git interpret-trailers`.
- A split/squash can duplicate or lose a trailer; the tool must be idempotent and re-add missing
  lines, never delete existing ones.

## 6. What this means for `jj-meta`

- Default to `Assisted-by: <harness>:<model>`; this is the Nixpkgs-compliant disclosure.
- Add `Session-Id:` when a session is known; it is the local attribution key. Make suppression easy.
- Do not add `Co-authored-by:` by default. Offer `--coauthor` for projects that require the GitHub
  avatar convention, and use the agent identity, never the human author.
- Never add `Signed-off-by:` for an agent; that is the human’s DCO certification.
- Append only missing trailers, deduplicate exact lines, preserve the body and existing metadata.
- Restrict to mutable changes by default; rewriting immutable history is not the tool’s job.

## 7. Sources

- Nixpkgs transparency policy:
  <https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md#transparency>
- OpenInfra / Nova commit messages (AI attribution):
  <https://docs.openstack.org/nova/latest/contributor/commit-messages.html>
- LocalAI AI coding assistants policy:
  <https://github.com/mudler/LocalAI/blob/13fe37df/.agents/ai-coding-assistants.md>
- Flux commit-assisted-by skill:
  <https://github.com/fluxcd/agent-skills/blob/main/internal/skills/commit-assisted-by/SKILL.md>
- Linux kernel coding assistants:
  <https://docs.kernel.org/process/coding-assistants.html>
- GitHub co-authored-by documentation:
  <https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors>
- Claude Code attribution setting:
  <https://docs.anthropic.com/en/docs/claude-code/settings>
- Codex co-author discussion:
  <https://github.com/openai/codex/discussions/2807>
- Copilot co-author trailer issue:
  <https://github.com/github/copilot-cli/issues/2188>
- Cursor/agent attribution reference:
  <https://www.refolk.ai/guides/agent-bot-commit-signal-reference>
- Assisted-by provenance article:
  <https://www.baristalabs.io/blog/ai-assisted-commits-need-provenance-trailer>
