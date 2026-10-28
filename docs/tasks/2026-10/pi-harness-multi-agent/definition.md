---
type: Task
description: Explore the Pi coding agent as a harness for multi-agent work — a high-effort orchestrator advised by an architect/reviewer and delegating to smaller, faster, better-suited models — and price the build against what opencode already does.
status: open
authored_by: agent
timestamp: 2026-10-27T22:45:00+01:00
---

# Pi as a multi-agent harness

## Why

opencode already drives the fleet: one primary agent plus a `Task` tool whose
`subagent_type` is a purpose alias
([../opencode-subagent-model-routing/done.md](../opencode-subagent-model-routing/done.md)).
That works, and it is what the three host tasks use.

Pi is the other coding agent in this repository
(`modules/den/aspects/dev-llm-pi.nix`, `pkgs.pi-coding-agent`). It differs in ways
that matter for orchestration: it has an SDK, an RPC mode, file-based sessions, a
per-run tool allowlist, per-run model and thinking depth, and a TypeScript
extension system that can spawn processes. It has **no built-in sub-agents**, and
that is the thing to price.

The target workflow is the same one the host tasks assume:

```
        architect / reviewer  (strong, sees plans, does not act)
                  ^  advise
                  |
   orchestrator (high effort, slow, decides and delegates)
       |            |            |
   small fast   small fast   vision / code / shell
    workers      workers       specialists
```

The question is not "is this possible in Pi" — the docs say it is. The question
is **how much work**, and whether it beats the opencode route on something we
actually care about: per-agent model choice, tool isolation, resumable sessions,
and auditable delegation.

## Runtime targets

Pi runs **on NixOS, or inside a `devenv` shell on Linux, NixOS or Darwin**. Both
routes matter and cost differently:

- **NixOS host**: `modules/den/aspects/dev-llm-pi.nix` already registers the app
  through `kdn.apps.pi` and keeps `~/.pi` across a wipe. A NixOS service or a
  `zellij` pane is the natural home, and the sandbox and credential rules from
  [isolation.research.md](isolation.research.md) apply.
- **`devenv` shell**: this repository's own `devenv.nix` is the pattern (it wires
  opencode, its providers and its agents). Pi in a devenv needs the same three
  things: the package on `PATH`, a provider entry for `brys`, and the
  extensions/skills/agents on disk. On Darwin the isolation options shrink: no
  bubblewrap, so the boundary is a container or nothing.

The current divergence: nixpkgs packages **1.1.0**, upstream is **1.4.0**. The
version in use must be pinned explicitly, because a flag or a builtin extension
that exists in one may be absent in the other.

## Research already done

| File | What it settles |
|---|---|
| [research.md](research.md) | The mechanism comparison from Pi's own docs: no built-in sub-agents, the two delegation routes, what each harness does better. |
| [isolation.research.md](isolation.research.md) | Pi runs with the user's full permissions; the four isolation routes mapped onto this homelab; SSH-CA instead of long-lived keys; the pane-as-subagent design; what context files Pi reads (`AGENTS.md` from cwd and parents, `.agents/skills` as a trust-protected resource). |
| [models.research.md](models.research.md) | No discovery for a compatible endpoint — `models.json` needs an explicit id list, so a generator from `llm-routers.nix` is required. The model cannot switch itself mid-turn; the *orchestrator* chooses the model per delegation. |
| [costs.research.md](costs.research.md) | Usage lives in the session JSONL and in `--mode json` events; local models cost **zero money** but real wall time; the two-currency accounting model and a delegation-cost formula. |
| [packaging.research.md](packaging.research.md) | nixpkgs **unstable already carries 1.4.0** (merged 2026-10-22) while our pin has 1.1.0, so the fix is a pin update or a `.flake.patches` entry, not a fork. Declarative surface, devenv wiring, and how to ship an extension with npm deps. |
| [sessions-and-panes.research.md](sessions-and-panes.research.md) | Session JSONL v3 and how to read it safely; the last-text-message extraction; `agent_settled` as the completion signal; why the session file beats `--mode rpc` over a zellij pty; the pane invocation and a `zellij-llm pi` group; ~6k fixed input tokens per child. |

## Decisions already implied by the research

1. **Delegation = a zellij pane per sub-agent**, with the session file as the
   result channel and `zellij action close-pane` as the stop button. It reuses
   `zellij-llm`'s naming and run-marker conventions.
2. **Model choice is a generator, not a hand-written list.** `models.json` comes
   from `hosts/brys/llm-routers.nix`, aliases only, with a `capability → alias`
   map for the delegation tool.
3. **Two currencies in the accounting**: local tokens and wall time (money = 0),
   and real USD for the SaaS overseer. Never mixed.
4. **Pin Pi explicitly.** Use 1.4.0 via a pin update or a `.flake.patches` entry
   (see the `flake-patches` skill); do not rely on whatever the lock resolves to.

## What to determine

1. **Delegation mechanism.** Two documented routes:
   - an **extension** that registers a tool and spawns `pi -p` subprocesses
     (`docs/extensions.md` lists a built-in `subagent/` category doing exactly
     this with `registerTool` + `exec`);
   - the **SDK** (`@earendil-works/pi-coding-agent`, `createAgentSession`,
     `SessionManager.inMemory()`, event subscription) embedding several agents in
     one process.
   Which one gives a better audit trail, and which one lets each worker run a
   *different* model without extra plumbing?
2. **Per-agent model and depth.** A worker must run a small fast model while the
   orchestrator runs a slow capable one. Determine whether that is a per-call
   parameter, a per-extension setting, or one process per agent.
3. **Tool isolation.** `--tools` / `--exclude-tools` exist per run. Can a reviewer
   be given read-only tools while a worker gets `bash` and `edit`? Prove it, and
   note whether an extension tool can be revoked the same way.
4. **The advisor loop.** An architect/reviewer that sees plans and replies, but
   never edits. Is a long-lived second session (`--session-id`, `--fork`) the
   right shape, or a one-shot `pi -p` per review with the plan as input?
5. **Local models.** Pi must talk to the `brys` fleet through the compat proxy.
   `docs/llama-cpp.md` and `docs/providers.md` describe local providers; confirm
   a purpose alias works as a Pi model id, and record the config.
6. **Sessions and audit.** Sessions are files, with `--session-id`, `--fork`,
   `--export` to HTML. Determine whether that gives a usable transcript per agent
   for the fleet evaluation
   ([../gaz-den-workstation/003-fleet-evaluation/definition.md](../gaz-den-workstation/003-fleet-evaluation/definition.md)).
7. **Headless operation.** `--mode json` and `--mode rpc` plus `--print` are the
   non-interactive surfaces. Determine if an orchestrator can run unattended,
   and how it reports progress.
8. **Cost against opencode.** Same workflow, both harnesses, one small task each.
   Count: lines of custom code, moving parts, and whether the delegation is
   visible to a supervisor.

## The honest comparison

| Concern | opencode today | Pi, as documented |
|---|---|---|
| Sub-agents | built in (`subagent_type`) | must be built (extension or SDK) |
| Per-agent model | per agent config, aliases generated from `llm-routers.nix` | per run (`--model`, `--thinking`) |
| Tool isolation | permission config | per-run `--tools` allowlist |
| Sessions | database, `opencode export` | files, `--session-id`/`--fork`/`--export` |
| Programmatic control | `opencode run`, server API | `--mode rpc`, SDK |
| Extensibility | plugins in TypeScript | extensions in TypeScript |
| Local fleet | native provider with discovery | provider config, must be confirmed |

Nothing above is a verdict. It is the list the task must fill with evidence.

## Deliverables

1. `research.md` with the mechanism comparison, quoting the docs and one working
   probe per mechanism.
2. A **spike** that runs the three-role workflow on a trivial task: orchestrator →
   one small worker → one architect review. It can be thrown away; it must run.
3. A recommendation: adopt Pi for the harness, adopt Pi for a specific part (for
   example the architect/reviewer, which is a read-only long-context role), or
   stay on opencode. State the reason and what would change the answer.
4. If adopted, a doc under `docs/` and a skill entry, in the same style as
   `docs/mcp-setup.md`.

## Acceptance

- The three-role spike runs end to end, with a transcript that shows different
  models in different roles.
- The spike shows tool isolation: the reviewer cannot edit a file.
- A measured statement of the build cost: how many lines, how many processes,
  what the supervisor can see.
- The recommendation cites a concrete difference, not a preference.

## Risks

| Risk | Mitigation |
|---|---|
| Building a sub-agent framework from scratch is a project in itself | timebox the spike; if the extension route needs more than a day, say so and stop |
| Pi's per-run model choice makes every worker a new process with a cold model load | measure it; brys loads are 30–120 s, so persistent workers may be required |
| Two agent frameworks in one repository doubles the documentation burden | prefer one; only adopt Pi for a role that opencode does badly |
| Sessions on disk hold prompts and code | treat them as user data, keep them out of git |

## Open questions

- Which Pi version is the baseline? The CLI here reports 1.1.0 while the store
  copy is 0.85.1, so the packaged versions diverge.
- Does Pi's compaction behave well with a 1M-context local model, or does it
  compact far too early?
- Does Pi support MCP servers, so the NanoKVM MCP becomes available to a Pi-based
  agent the same way it is to opencode? `pi mcp` exists in the CLI.
