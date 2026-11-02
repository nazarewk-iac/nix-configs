---
type: Research
description: How Pi chooses a model — declarative declarations, per-run flags, interactive cycling, and what "the model decides" can and cannot mean — and the generator this repository needs for the brys fleet.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T11:40:00+01:00
---

# Model selection in Pi

Sources: Pi v1.4.0 `models.md`, `configuration.md`, `cli.md`, `extensions.md`, and
the installed 1.1.0 CLI.

## 1. There is no automatic discovery for a compatible endpoint

A compatible endpoint is declared in `models.json` with an **explicit model list**:

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [{ "id": "qwen2.5-coder:7b" }]
    }
  }
}
```

So Pi does **not** call `/v1/models` and adopt what it finds. This is the opposite
of the opencode setup in this repository, where
`kdn.llm.client.upstreams.brys.discovery.enable` lists every served id
automatically ([hosts/oams/devenv.nix](../../../../hosts/oams/devenv.nix)).

Verified on the installed CLI: with no provider configured, `pi --list-models`
prints `No models available`. The bundled catalog gives nothing without
credentials, so `models.json` is the only way in for a local fleet.

Discovery is possible, but it is an extension: `models.md` says

> Use an extension when the provider needs custom streaming, **model discovery**, or
> authentication behavior.

That is a real option for us — an extension that reads the proxy's `/v1/models`
and registers them — and it is the only way to keep Pi's list in step with the
server without a generator.

## 2. Credentials never need to sit in a file

`apiKey` accepts three forms: a literal, `$NAME`/`${NAME}` environment
interpolation, or a leading `!command` that runs **at request time** and is not
cached. So the brys key can be read from its existing path:

```json
"apiKey": "!cat /run/configs/llms/llama-server/api-keys/default"
```

That keeps the secret out of the Nix store and out of the repo, which the other
harness achieves by a wrapper environment file.

## 3. Run-time selection, in the order you will use it

| Surface                                              | Effect                                                               |
| ---------------------------------------------------- | -------------------------------------------------------------------- |
| `--model <provider>/<id>` (optionally `:<thinking>`) | pin one model for the run                                            |
| `--provider <name>`                                  | disambiguate when a pattern matches several providers                |
| `--thinking <off…max>`                               | reasoning depth for that run                                         |
| `--models <patterns>`                                | comma-separated globs/fuzzy patterns for the `Ctrl+P` cycle          |
| `/model`, `/scoped-models`                           | interactive switch, and control over the cycle list (saved)          |
| `--list-models [search]`                             | what is actually available, with fuzzy search                        |
| `modelOverrides` in `models.json`                    | change metadata for an existing model without replacing the provider |

`/ui`-style discovery is absent; `--list-models` is the discovery command.

## 4. Can the model decide which model to use?

Two different questions, two different answers.

**Mid-turn, no.** A running session has one model. Pi has no tool that switches
the active model from inside a turn, and `codemode`'s `models` global explicitly
lists chat models as _not runnable_ from a script:

> Chat models are listed but cannot be run from scripts.

**At the delegation layer, yes — and this is exactly the orchestrator pattern.**
In the subagent example, each agent is a Markdown file with frontmatter:

```markdown
---
name: reviewer
description: Code review specialist for quality and security analysis
tools: read, grep, find, ls, bash
model: claude-sonnet-4-5
---
```

so the orchestrator's choice of _agent_ is the model choice. The dispatch then
runs `pi --model <that model>`. Nothing stops a delegation tool from exposing
`{ agent, task, model? }` so the orchestrator can pick a model per task, or from
exposing a small "capability" enum (`{ tier: "fast" | "std" | "deep" }`) that the
tool maps to an alias, which is the fleet-friendly shape.

So the accurate statement: **the orchestrator decides the model per delegation;
the model never decides for itself mid-turn.** A per-token router would need an
extension that re-dispatches, and that is a different (worse) design.

## 5. What this repository needs

`hosts/brys/llm-routers.nix` already owns the alias map, and
`hosts/brys/llm-agents.nix` turns it into opencode subagents from one file. Pi
needs the same single source of truth, or the two harnesses will drift:

1. **A generator** (`kdn-pi-models`, a few lines of Nix, in the style of
   `llm-agents.nix`) that writes a `models.json` with the purpose aliases as ids
   and the base ids behind them, `api: openai-completions`, the proxy `baseUrl`,
   and the `!cat` key form.
2. **Aliases only, by default.** 77 ids are unusable in a `Ctrl+P` cycle. The
   cycle should hold the orchestrator plus three or four workers; the rest stay
   reachable by `--model`.
3. **A capability map** for the delegation tool: `fast` → `tools-std-fast`,
   `deep` → `code-deep-slow`, `vision` → `vision-std-fast`. The tool translates,
   the orchestrator names an intent, and the server keeps the freedom to re-point
   the alias. This mirrors the alias scheme the fleet already uses.
4. **Keep the base ids out of the default cycle**, and note that a base id is a
   measurement, not a contract: the alias is the stable name.

## 6. Cost side of the choice, per the accounting research

- A local id costs **zero money** and real wall-clock time, so the model choice
  optimises tokens/s and queue wait, not price ([costs.research.md](costs.research.md)).
- A SaaS id (the overseer, or an escalation) is the only thing with a real price,
  and Pi reports it per session.
- Consequence: the model choice per role should be recorded in the same JSONL as
  the outcome, or a later comparison cannot attribute a change in quality to a
  change of model.

## 7. Not verified

- Whether `--model` accepts a bare alias that a provider declares with a different
  id (pattern matching) or requires the exact id. Test with a real `models.json`.
- Whether an extension can register models such that `/model` lists them without a
  restart.
- Whether the llama.cpp-router integration (`/llama`, which "discovers GGUF files
  and loads models on demand") could sit beside llama-swap, or whether the two
  routers conflict.
