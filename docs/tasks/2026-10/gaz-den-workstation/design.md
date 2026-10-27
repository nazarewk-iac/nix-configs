---
type: Design
description: The supervised-fleet harness: the exact startup commands, the model ladder and why it escalates that way, the overseer's watch loop with thresholds, the loop detector, the oracle channel, and the physical hand-off protocol.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T19:30:00+01:00
---

# Design: one orchestrator, many cheap workers, one supervisor

The point of the layout is that the **slow** model does the thinking and the
**fast** models do the touching. The supervisor exists because a slow model that
loops is expensive in wall-clock time, and a fleet that evicts its own frontier
is invisible from inside the session.

## 1. The roster

| Role | Where it runs | Model | Why this one |
|---|---|---|---|
| Overseer | one opencode session, this shell | SaaS (`requesty/deepseek-v4.1-flash-1017` in the reference run) | It must be fast, cheap to keep open for hours, and better than the local models at unblocking. |
| Orchestrator | one opencode session in Zellij | `brys/qwen3.8-flash-next` at thinking `high` | Capable, 1M context, accepts images, and it is the alias the fleet already labels "orchestrate". |
| Workers | sub-agents of the orchestrator | aliases, see the ladder | Start cheap, escalate on evidence. |
| Owner | the physical world | — | Only hands in the system. |

The overseer and the orchestrator never share a session. The overseer talks to
the orchestrator only through `zellij-llm opencode send`, so every instruction is
visible in the pane and in the transcript.

## 2. Startup

Phase 0 must settle the orchestrator's thinking depth, because the TUI has no
depth flag (see [research.md](research.md#7-session-tooling)). Two options, in
order of preference:

1. **Add a primary agent.** Define `orchestrator` with
   `mode = "primary"`, `model = "brys/qwen3.8-flash-next"`, and
   `options.chat_template_kwargs = qwenThinking.high`, beside `mkAgents` in
   `hosts/oams/devenv.nix`. Then:

   ```bash
   zellij-llm opencode spawn --pane orchestrator \
     --model brys/qwen3.8-flash-next \
     --opencode-arg '--agent' --opencode-arg 'orchestrator' \
     --opencode-arg '--auto'
   ```

2. **Fallback, no config change.** Spawn the default `build` agent on the alias:

   ```bash
   zellij-llm opencode spawn --pane orchestrator \
     --model brys/orchestrate-deep-slow --opencode-arg '--auto'
   ```

   This works, but the depth is whatever the alias maps to on the server, and
   that is not guaranteed to stay `high`. Record which one the run used.

Then send the opening brief and follow the first turn:

```bash
zellij-llm opencode send --pane orchestrator --text "<the brief>"
zellij-llm opencode watch --pane orchestrator --for 2h
zellij-llm opencode list          # pane → opencode session id
zellij-llm opencode attach        # the command to give the owner
```

`--auto` is needed, and it is a real risk. The permission baseline in the
`opencode` aspect still denies what it denies; the harness must additionally
ensure no remote push is possible (no credentials for the fleet, `jj` only, and
the owner pushes).

## 3. The ladder

Start at the top of this table and only move down on evidence. "Evidence" means
the worker returned a wrong or unusable answer **twice**, or the task is
obviously beyond the tier.

| Tier | Aliases | Served model | Use |
|---|---|---|---|
| micro | `tiny-dumb-fast`, `tiny-dumb-fast-alt` | qwen3.5-0.8b / qwen3.5-2b (GPU) | routing, classification, one-field extraction |
| fast | `chat-dumb-fast`, `code-quick-fast`, `tools-dumb-fast` | qwen3.5-4b (GPU) / granite-4.2-3b | one small edit, one shell command, one rewrite |
| std | `chat-std-fast`, `code-std-fast`, `tools-std-fast`, `vision-std-fast` | lfm2.5-24b-a2b (CPU), north-mini-code-1.0, qwen3-vl-30b-a3b | the normal working tier |
| deep | `chat-deep-slow`, `code-deep-slow`, `reason-deep-slow`, `vision-deep-slow` | qwen3.8-27b (CPU, dense, ~2.5 t/s) | genuinely hard reasoning, careful code |
| orchestrator | `orchestrate-deep-slow` | qwen3.8-flash-next | planning and review only |

Rules the orchestrator must follow, and the overseer must enforce:

1. **Never** hand a long open-ended loop to a `dumb` or `quick` alias. Those
   models obey tight instructions and fail confidently on ambiguity.
2. One task, one exact output shape, per worker call. "Rewrite this file so that
   X" — not "improve the config".
3. Prefer `vision-quick-fast` for a KVM screenshot with one question ("what text
   is on the blue button?"). Use `vision-std-fast` for a layout question. Use
   `vision-deep-slow` only when the first two disagree.
4. Do not fan out to one alias many times. Fan out across **different** aliases;
   see the concurrency note below.

### The concurrency budget, as measured

- Every non-frontier model is `--parallel 1`. Five calls to `chat-dumb-fast` are
  five calls to the **same** process, so they run one after another.
- `chat-dumb-fast`, `code-quick-fast`, `tiny-quick-fast` and `grunt` are all
  **one** process (`qwen3.5-4b` on Vulkan0). Treat them as a single worker.
- The frontier runs `--parallel 4` with unified KV, so the orchestrator's own
  requests do not queue behind workers.
- 15 models share 8 GB of VRAM. Two or three small GPU models fit together; a
  4B plus a 9B plus a 0.8B is roughly 6 GB. More than that starts evicting.
- CPU workers contend for ~40 GB/s and **halve** the frontier while resident.
  So a `std` worker beside the orchestrator is a borrowed slowdown, not free
  parallelism. Use it for a burst, then let it unload.

Practical recipe: **one GPU worker tier for chatter, one CPU worker for real
edits, and the orchestrator on the frontier.** Do not run three CPU tiers at
once.

## 4. The watch loop

The overseer runs one cycle every 5–10 minutes while `watch` reports RUNNING.
Each cycle is cheap and read-only. Any threshold hit produces one short `send`.

```bash
# 1. is the turn still running, or has it gone idle or died?
zellij-llm opencode watch --pane orchestrator --for 5m

# 2. did a model die or get evicted?
ssh kdn-brys 'curl -s http://127.0.0.1:39700/running; journalctl -u llama-swap --since "-10min" -o cat | grep -iE "oom|killed|evict|error|timeout" | tail'

# 3. is brys itself healthy?
ssh kdn-brys 'cat /proc/loadavg; free -g | head -2'
# VRAM on the W6600 is card1 (8.57 GB). card0 is the 4 GB iGPU.
ssh kdn-brys 'for c in /sys/class/drm/card*/device; do [ -e "$c/mem_info_vram_used" ] && \
  echo "$c used=$(cat $c/mem_info_vram_used) total=$(cat $c/mem_info_vram_total)"; done'

# 4. is the KVM's HID path still alive? (only when a GUI step is in play)
ssh root@kvm-fa56... 'ioreg -c IOHIDSystem | grep HIDIdleTime'   # must reset after each injected key

# 5. is the orchestrator actually progressing?
jj -R ~/dev/github.com/nazarewk-iac/nix-configs log -r '@|@-' --no-graph
```

Thresholds and the action for each:

| Signal | Threshold | Action |
|---|---|---|
| `state=RUNNING` for one turn | > 25 min without a new tool call | interrupt with a scoped instruction ("stop, report what is blocking you in 5 lines") |
| Same tool call repeated | 3 times | name the loop explicitly and forbid the call |
| Same file edited | 5 times with no progress | send the diff and ask for a decision or the overseer's answer |
| `jj log` unchanged | 40 min of work | ask for a plan checkpoint; consider resetting the sub-goal |
| Fleet eviction in the log | any `evict` of the frontier | tell the orchestrator to wait for the swap, not retry |
| `free -g` available | < 8 GB | stop CPU worker bursts |
| brys load average | > core count for 10 min | serialise; do not spawn more |
| KVM `HIDIdleTime` climbing after a key | 2 samples | stop GUI work, report, prefer a fresh session |
| `cube_screenshot` error | 3 attempts | stop, ask the owner to power the machine |

The overseer writes one line per cycle into
`docs/tasks/2026-10/gaz-den-workstation/.worklog.md` (git-ignored). That file is
the raw material for the evaluation.

## 5. The oracle channel

The orchestrator may ask the overseer for help. It does so with one short
message in its own pane, beginning `OVERSEER:` and naming the blocker. The
overseer answers through `send` with the smallest fact that unsticks it: a file
path, a command, a decision, or a corrected assumption.

Rules:

- The orchestrator asks **early**. Two failed attempts and it asks; it does not
  try a third variant of the same idea.
- The overseer may answer as a stronger model, but it must not take over the
  work. It gives a fact, not a patch, unless the patch is the fact.
- Every question and answer is logged. This is evaluation data: "which problems
  needed a SaaS model" is part of the answer we want.

## 6. The physical hand-off protocol

Any step that needs hands follows the same shape.

1. The orchestrator writes a `HANDS:` line that states, in one sentence, what
   the owner must do. Example: "HANDS: hold the power button for 3 seconds,
   then release, then tell me when the fan starts."
2. The orchestrator **stops**. It does not busy-poll the KVM for a minute.
3. The overseer relays it to the owner in chat and waits.
4. The owner confirms in chat.
5. The overseer sends the confirmation into the pane.
6. The orchestrator verifies with a screenshot **before** acting again.

Screenshot rules, from the `anji` experience:

- Save each shot as `/tmp/opencode/nanokvm/NN-name.jpg`. Never commit it.
- Wait 2 s after any injection, then take the shot. The feed lags.
- Poll until the frame matches the expected state; do not fire a second action
  into a frame that has not changed.
- If the feed is black, send one `Shift`, wait 2 s, shoot once more. Still black
  means no signal, and that is a `HANDS:` item.

## 7. What the evaluation records

Per turn: start, end, the alias used, whether it was accepted, and the reason it
was rejected.

Per phase: which tier was enough, how many escalations, how many oracle calls,
how many owner hand-offs.

Global: the longest single turn, the wall-clock spent waiting on model swaps, the
peak RAM and VRAM, and every OOM or eviction.

The report goes in [003-fleet-evaluation](003-fleet-evaluation/definition.md).
Numbers only. An estimate is labelled as an estimate.

## 8. Stop conditions

The run stops, and the overseer reports to the owner, when any of these is true:

- the KVM shows no signal twice in a row after a power hand-off;
- `brys` loses a model repeatedly within one phase;
- the orchestrator loops after two explicit corrections;
- an action would erase a disk whose identity the owner has not confirmed;
- the machine fails to boot twice from the new configuration.

A stop is not a failure. A stop that is well recorded is the most valuable data
the run produces.
