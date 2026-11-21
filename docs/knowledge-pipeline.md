---
type: Reference
description: The kdn-knowledge pipeline — read harness sessions, extract durable items with the local frontier, merge the repeats, and propose concepts and skills for the agent memory bundle.
timestamp: 2026-11-22T00:00:00+01:00
---

# kdn-knowledge

Turns finished sessions into short, deduplicated, searchable knowledge. Runs only on the local
fleet: the model is `qfn` on `brys`, and the endpoint guard refuses any host that is not on the
private network.

Design: [docs/tasks/2026-11/knowledge-pipeline/design.md](tasks/2026-11/knowledge-pipeline/design.md).
Task: [docs/tasks/2026-11/knowledge-pipeline/definition.md](tasks/2026-11/knowledge-pipeline/definition.md).

## The four steps

| command   | what it does                                                                                | writes                                                 |
| --------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `harvest` | reads `~/.local/share/opencode/opencode.db`, normalises each session, drops reasoning parts | `corpus/<session>.json`                                |
| `extract` | one `qfn` call per session, strict JSON contract, one repair attempt                        | `candidates/<session>.json`                            |
| `dream`   | lexical clustering, one merge call per cluster, comparison with the bundle                  | `proposals/<ts>/{concepts,skills,plan.json,report.md}` |
| `apply`   | hands the concepts to the bundle writer, then validates                                     | `.agents/knowledge/**`                                 |

`run` is the first three and stops before `apply`.

## The run, from a laptop, over NetBird

The endpoint is `https://llama-swap.brys.priv.nb.net.int.kdn.im/v1` and it resolves to brys'
NetBird address, so the same command works on the LAN and in another city. The bearer key is a file
that already exists on every host, and the tool reads it itself: `--key-file` (or
`KDN_KNOWLEDGE_KEY_FILE`) overrides the default `/run/configs/llms/llama-server/api-keys/default`.
There is no key variable to export. What the tool resolved:

```bash
kdn-knowledge status    # endpoint, key file, corpus, estimate, and the placement verdict
```

A first pass that you can watch:

```bash
kdn-knowledge harvest --project ~/dev/github.com/nazarewk-iac/nix-configs
kdn-knowledge extract --limit 20
kdn-knowledge dream
less ~/.cache/kdn/knowledge/proposals/*/report.md
```

A full pass, detached, survives a dropped ssh session because every finished session is written
to `state.json` before the next one starts:

```bash
systemd-run --user --unit kdn-knowledge --collect \
  kdn-knowledge run --project ~/dev/github.com/nazarewk-iac/nix-configs
journalctl --user -u kdn-knowledge -f
```

Resume after a stop is the same command: a session whose content hash is unchanged is skipped.
`--force` re-extracts everything.

### Very long sessions

A session over the model window fails with a clear reason instead of being truncated:

```
the transcript of ses_... is 2021338 characters, over the model window; pass --chunk-chars 24000
```

Retry those with chunking; `extract` retries `failed` sessions on its own, so nothing is lost:

```bash
kdn-knowledge extract --chunk-chars 24000 --max-chunks 12
```

A reply that is not valid JSON after one repair is the other failure mode; it is recorded with the
parser error and does not stop the run.

## What it costs

`extract` prints a running average and the estimate for the sessions that remain; `status` prints
the same estimate from the sessions that are already finished. On 2026-11-21 the runs measured
54.3 s per session ("~2.9 h for 192 remaining"), then 64.6 s ("~3.6 h for 200 remaining"), and by
00:40 the average over 73 finished sessions had settled at **45.0 s** ("~2.5 h for 200 sessions").
A long session costs more than a short one, so the average moves as the corpus fills: read the line
the tool prints, not this paragraph.

Those 73 sessions produced **254 items**, and a spot check says they are distinct: a `pkgs.buildEnv`
file-vs-directory pitfall, `microvm.nix` VFIO passthrough, an IFB device for ingress shaping, the
llama-swap metrics ring traps, the VHS never-upscale rule. Repetition does exist and merges — the
"deploy `brys` with `./nixos-rebuild.sh switch remote=brys`" pair and the "`data/llm.nix` is the
single source" pair each became one concept — but most items are genuinely new, so the proposal cap
(`--max-concepts`, default 60) is the review lever, not the merge threshold.

**27 of those 73 sessions produced an empty list**, and that is a success: a short session that
fixed a typo carries nothing that will still be true next month, and the prompt asks for `[]` in
that case. `status` counts extracted sessions; `dream` counts the ones with at least one item, so
the two numbers differ by exactly that many.

Nothing switches, nothing unloads, and no second model competes for the card, because every call
goes to the frontier that is already loaded on the resting profile.

A llama.cpp grunt model cannot do this on the resting profile: `gemma-4-e4b` and
`ministral-3-3b-reasoning` are refused beside `max-multi` and only start on a colo profile
(`qfn-fast-colo`), which costs a 58–74 s switch.

## Reading the proposal

`report.md` gives the counts, the strongest clusters and every failed session with its reason.
`plan.json` is the same thing for a script. Each concept is one file with the bundle's frontmatter
and `status: draft`; nothing is `stable` until a human says so.

`apply --yes` creates the concepts through `okf-memory create`, so `log.md` and the directory
`index.md` stay coherent, then runs three gates in order: `ai-xf-canon check` (with a rewrite of
every non-canonical file), `okflint validate --manifest .agents/knowledge/okf-base.yaml
.agents/knowledge`, and `ai-xf-validate .agents/knowledge --level 2`. A missing gate binary is a
printed warning, not a failure. It refuses to overwrite a concept whose status is `stable`, and a
failing gate removes the concepts this run created and restores the bookkeeping files.

`okf-memory create` leaves out one field that the repo's AI-XF Level 2 gate requires: `id`.
`apply` therefore inserts `id: <file-slug>` directly after `type:` in every concept it creates —
the canonical position — and leaves the rest of the file byte-identical. A concept that already
carries an `id` is left alone, so an update of an older concept also becomes conformant. `links`
is still the writer's gap: `okf-memory` does not set it, AI-XF Level 2 does not require it, and a
human adds relations when a concept needs them.

## Searching the result

```bash
okf-memory search "jj split worklog" .agents/knowledge --limit 5
kdn-okf list --type Decision --status draft    # the new drafts, once applied
```

## Guard rails

- The endpoint must pass the host allow-list (`--allow-host` adds one). `api.openai.com` is
  refused by construction.
- The tool never switches profiles and never unloads a model.
- The bundle has one writer: `apply` goes through `okf-memory`, and the pipeline never touches
  `index.md` or `log.md` itself.
