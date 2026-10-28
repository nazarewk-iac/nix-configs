---
type: Research
description: Pi session file format and lifecycle, why the session file beats RPC as the result channel over a zellij pty, the pane invocation, and a zellij-llm pi command group.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T11:45:00+01:00
---

# Pi panes: research and design for a session-file delegation tool

Draft. Read-only research. No repository change.

## Versions and sources

| Label | Source |
|---|---|
| **pi-1.4.0** | `https://raw.githubusercontent.com/earendil-works/pi/v1.4.0/packages/coding-agent/docs/*.md` and `examples/extensions/subagent/*` |
| **pi-0.85.1** | `/nix/store/qf702rins357mp8jlr1s5k1s3kp2d2ms-pi-coding-agent-0.85.1/lib/node_modules/pi-monorepo/docs/` and `dist/core/session-manager.js` |
| **pi-1.1.0** | the installed CLI, `pi --version` = `1.1.0`, `pi --help` |
| **zellij-0.45.1** | the installed CLI, `zellij --version`, `zellij action <cmd> --help` |
| **repo** | `packages/llm/zellij-llm/zellij-llm.sh`, `.agents/skills/zellij/SKILL.md`, `docs/tasks/2026-10/zellij-llm-opencode/done.md` |

Installed pi is **1.1.0**. Upstream is **1.4.0**. The session-file behaviour below is
checked in the **0.85.1** source tree. Marked items are unverified.

---

## 1. Session file format and flags

**Format (pi-1.4.0 `session-format.md`):** JSONL. One JSON object per line. Each line has a
`type`. Version 3 is current. Entries form a tree with `id` and `parentId`.

Entry types (pi-1.4.0): `session` (header, first line), `message`, `model_change`,
`thinking_level_change`, `usage`, `compaction`, `context_edit`, `branch_summary`, `custom`,
`custom_message`, `label`, `session_info`.

`session` header example (pi-1.4.0):

```json
{"type":"session","version":3,"id":"uuid","timestamp":"...","cwd":"/path","parentSession":"..."}
```

**Location (pi-1.4.0):**

```
~/.pi/agent/sessions/--<path>--/<timestamp>_<session-id>.jsonl
```

`<path>` is the working directory with the leading `/` removed and `/`, `\`, `:` replaced by
`-`. `<session-id>` is a UUID unless the caller sets it.

**Flag interaction (pi-1.4.0 `cli.md`, confirmed in `pi --help` 1.1.0):**

| Pair | Rule |
|---|---|
| `--session <path\|id>` + `--session-id` | Not allowed together (1.4.0 constrains `--session-id` with `--session`). |
| `--fork <path\|id>` + `--session` / `--continue` / `--resume` / `--no-session` | Not allowed. `--fork` + `--session-id` is allowed and names the new session. |
| `--session-dir <dir>` | Highest precedence over `PI_CODING_AGENT_SESSION_DIR` and the `sessionDir` setting. |
| `--continue` / `-c` | Most recent session for this cwd. |
| `--session-id <id>` | Opens the exact project session id, or **creates it if absent**. This is the flag the tool needs. |
| `--no-session` | In-memory only. Not resumable. |

The `--session-id` "create if absent" rule is the key fact for a delegation tool: a fresh
`--session-id` gives a deterministic path you can read before the child starts.

---

## 2. Is the file safe to read while the child writes it?

The docs do **not** state flush semantics. The **0.85.1 source** does, and it is more careful
than the docs suggest.

- Steady state: each finished entry is one `appendFileSync(file, JSON.stringify(entry) + "\n")`
  call (`dist/core/session-manager.js:745,766`). `appendFileSync` opens, writes, closes per call.
  There is no long-lived buffer. Whole lines appear in order.
- Creation: the file is **not created until the first assistant message exists**
  (`_persist`, `:739-769`). Before that, entries stay in memory. On the first assistant message
  the whole prefix is written with `openSync(file,"wx")` (exclusive create). So a reader can see
  **no file at all** while the child is thinking.
- Rewrite: `_rewriteFile()` (`:708-718`) and one migration path rewrite the whole file with
  `openSync(file,"w")` (truncate). A reader during a rewrite can see a short or empty file.
- Loader: `loadEntriesFromFile` (`:276-340`) **skips malformed lines** and appends a missing
  trailing `\n`. A torn final line is dropped and does not break the load.

**Answer:** safe to *tail* in steady state. Two hazards remain: the file may not exist yet, and
a whole-file rewrite truncates it briefly. Therefore the parent must (a) treat "no file" as
"running", (b) retry the parse, and (c) never trust a file mid-rewrite. A torn final line is
safe because the loader skips it.

Unverified for **1.4.0**: the write path is not in the vendored tree. Assume it is unchanged
until proven.

---

## 3. Robust extraction of the final answer

Do **not** use a `compaction` summary: it is a context summary, not the answer (pi-1.4.0
`session-format.md`). Do **not** use `--export`: it renders HTML (pi-1.4.0 `cli.md`), which is
lossy and needs a parser.

Use the **last assistant `message` entry that has a text block**, in file order. On a
non-branching run the last entry is the leaf, so file order equals branch order. Filtering on
"has text" skips a final assistant message that holds only a tool call.

```bash
jq -rs '
  [ .[] | select(.type=="message" and .message.role=="assistant")
        | select([ .message.content[]? | select(.type=="text") ] | length > 0) ]
  | last
  | { text: ( [ .message.content[] | select(.type=="text") | .text ] | join("\n") ),
      usage: .message.usage,
      stopReason: .message.stopReason,
      model: .message.model }
' session.jsonl
```

Text only:

```bash
jq -rs '[ .[] | select(.type=="message" and .message.role=="assistant")
          | .message.content[]? | select(.type=="text") | .text ] | last' session.jsonl
```

`jq -rs` reads the whole stream. To read a torn file safely, prepend a filter that ignores parse
errors: `jq -rs 'map(select(type=="object")) | ...'` does not help; instead pipe through
`grep -v '^$'` and accept that `jq` aborts on a bad line. Safer: read with the loader rule
(drop the last line if it does not parse) — the spike below does that.

Unverified: whether pi writes an assistant entry when the run fails before any text. The
subagent example falls back to `stderr` and `errorMessage` for that case (pi-1.4.0
`subagent/index.ts:184-188`), so mirror it.

## 4. Completion and abort signals

Source: pi-1.4.0 `cli-integration.md`, `json.md`, `rpc.md`.

**`--print` (pi-1.4.0 `cli-integration.md:22-32`):**
- Writes the **final assistant text to stdout**, then exits.
- A final response with `error` or `aborted` stop reason gives a **nonzero exit status**.
- A `length` (output limit) stop still prints partial text, warns on stderr, exits nonzero.
- No events. So: exit code + stdout is the whole signal.

**`--mode json` (pi-1.4.0 `json.md`, `cli-integration.md:39-50`):**
- One `session` header, then events, then exit.
- `agent_end` closes one low-level run. `agent_settled` (`aborted` flag) means Pi will not
  continue automatically. **Completion = `agent_settled`.**
- A failed or aborted assistant response **does not by itself set a nonzero exit status**
  (`cli-integration.md:46`). You must inspect the events or the exit reason. This is the trap.
- In **0.85.1** `json.md` has no `agent_settled`; only `agent_end`. So a 0.85.1-era child must
  use `agent_end` (or the session file). Treat `agent_settled` as 1.4.0+.

**Killed process:**
- The session file holds the entries appended so far (0.85.1 `_persist`). If the kill lands
  before the first assistant message, **no file exists**.
- A torn last line is skipped on reload (0.85.1 loader), so the session **stays resumable**.
- An aborted run can leave a final assistant message with `stopReason:"aborted"`. The parent
  must treat that as a failure, not as an answer.

**Practical rule:** the child's wrapper writes an **exit marker file** after the process ends
(the repo's existing convention). The marker is the primary completion signal. The session file
is the payload. A missing marker plus a dead pane is a crash.

---

## 5. `--mode rpc`: does it beat the session file?

**What it exposes (pi-1.4.0 `rpc.md`, `rpc-commands.md`):** a long-lived subprocess on
JSONL stdin/stdout. Commands: `prompt`, `steer`, `follow_up`, `abort`, `clear_queue`,
`get_state`, `get_messages`, `get_last_assistant_text`, `set_model`, `set_thinking_level`,
`compact`, `bash`, `switch_session`, `fork`, `clone`, `get_entries`, `get_tree`,
`set_session_name`, and more. Events: the full `json.md` stream. Failed commands return
`{"success":false,"error":...}` (pi-1.4.0 `rpc.md:73-89`). Shutdown is "close stdin"
(pi-1.4.0 `rpc.md:91-95`).

**Verdict: RPC is the better channel only when the parent owns the child's stdin.**
- For a direct `spawn` (the 1.4.0 subagent example), RPC or `--mode json` on a pipe beats the
  session file: no polling, real `abort`, typed commands, `get_last_assistant_text` returns the
  answer in one call (`pi-0.85.1 rpc.md:775`).
- **In a zellij pane it is the wrong tool.** `new-pane -- <cmd>` gives the child a **pty**, not
  a pipe. You cannot write to its stdin from the parent except by typing into the terminal
  (`write-chars` / `send-keys`), which races with the TUI line discipline and mixes the JSONL
  with terminal echo. `zellij action pipe` targets WASM plugins, not the child (repo
  `zellij-llm.sh:475-477`).
- Honest trade-off: RPC needs a persistent, bidirectional pipe and a reader that never stalls
  (pi-1.4.0 `rpc.md:51-56`). A pane gives you **observability** (a human can attach and watch)
  and **process isolation**, but not a clean control channel. So: **pane + session file for
  isolation and review; RPC only for a directly spawned child.** Do not build RPC-over-pane.

---

## 6. zellij mechanics (quoted from `.agents/skills/zellij/SKILL.md`, zellij-0.45.1)

- **Create a pane with a command:** `zellij --session <S> action new-pane --name <N> [--cwd DIR]
  [--close-on-exit] -- <cmd...>` (SKILL.md:290, `zellij action new-pane --help`). It returns the
  pane id as `terminal_<id>`.
- **Address by id:** pass `-p <id>` to `write-chars`, `send-keys`, `paste`, `write`,
  `dump-screen`, and `close-pane`. "A pane id is a plain integer, `terminal_<id>`, or
  `plugin_<id>`" (SKILL.md:301-302). Get ids from `action list-panes --json --all -s -c`
  (SKILL.md:62, 281). Filter `is_plugin:false`.
- **Without stealing focus:** `write-chars -p <id>` and `send-keys -p <id>` do not change the
  focused pane (SKILL.md:31-47, verified 2026-10-12). Submit a TUI line with `write -p <id> 13`
  (raw CR), not `send-keys Enter` (repo `zellij-llm.sh:590-597`).
- **Close it:** `zellij action close-pane -p <id>` (0.45.1 has the `-p` flag). Prefer this over
  `close-pane` with no `-p`, which closes the focused pane.
- **Environment inheritance:** **unverified.** `new-pane` runs inside the zellij server, so the
  pane inherits the **server** environment (the session creator), not the `zellij action` caller.
  Define every value inline in the command (`FOO=bar cmd`) or in a file. Do not rely on
  export from the parent shell.
- **Scrollback after the command exits:** a pane closes when its command exits, so the
  scrollback is lost. "You cannot recover the scrollback of a closed pane" (SKILL.md:27). The
  repo keeps the pane open by appending `exec "${SHELL:-bash}" -i` after the command
  (`zellij-llm.sh:166-172`, verified). `--close-on-exit` drops that and closes the pane.
- **Headless pitfall:** `new-pane --stacked` silently fails with no attached client
  (SKILL.md:314-318). Use plain `new-pane` then `action stack-panes`.

---

## 7. Failure detection: bad `--model` or missing provider

- A bad model id fails the command: RPC returns `{"success":false,"error":"Model not found:
  invalid/model"}` (pi-1.4.0 `rpc.md:78`). In print/json mode Pi exits **early** with a
  nonzero status and a stderr message (pi-1.4.0 `cli-integration.md:30`).
- Unknown provider: `--provider` "requires `--model`" and a fuzzy match with several providers
  either prefers one with credentials or **asks for `--provider`** (pi-1.4.0 `cli.md:63-66`).
  In a non-interactive pane the ask cannot complete, so the child must be pinned to
  `provider/model` (**unverified** exact non-TTY behaviour; pin the provider to avoid it).
- **Parent fast-notice:** the pane wrapper writes the exit marker right after the process ends
  (`zellij-llm.sh:180-190`). A startup failure writes the marker in under a second. The parent
  waits for the marker with a **startup deadline** (for example 15 s). If the marker is absent
  and the pane has no running command (`list-panes` `exited:true` or `terminal_command` empty),
  report `spawn failed` and read stderr, instead of waiting for the full run timeout.
- The subagent example reads stderr and reports it when a child exits before output
  (pi-1.4.0 `subagent/README.md:117`, `index.ts:184-188`). Mirror that.

---

## Design

### A. The pane invocation for one sub-agent

Per role, read the agent markdown frontmatter (pi-1.4.0 `subagent/agents.ts`,
`agents/*.md`): `name`, `model`, `tools`, and the body as the system prompt. Build the argv
with `%q` quoting (repo `_opencode_command`, `zellij-llm.sh:670-690`) so the pane's
`bash -xeEuo pipefail` runs it unchanged.

```bash
session="$(zellij-llm pi _session-name)"        # same derived llm:<repo>:<sid>:pi convention
role=scout; task='find all auth code'
prompt_file="$run_dir/prompt-$role.md"          # from agents/<role>.md body, mode 0600
session_file="$run_dir/pi.jsonl"                # deterministic path for this run
model='anthropic/claude-haiku-4-5'              # frontmatter, or inherited model
tools='read,grep,find,ls,bash'                  # frontmatter, omit => Pi default
thinking='medium'

zellij --session "$session" action new-pane \
  --name "pi-$role" \
  --cwd "$PWD" \
  -- bash -c '
    set -o pipefail
    pi --mode json -p \
       --session "$1" \
       --model "$2" \
       --thinking "$3" \
       --tools "$4" \
       --append-system-prompt "$5" \
       -- "Task: $6" >"$7" 2>"$8"
    printf "%s" "$?" >"$9"
  ' _ \
  "$session_file" "$model" "$thinking" "$tools" \
  "$prompt_file" "$task" "$run_dir/events.jsonl" "$run_dir/stderr" "$run_dir/exit"
```

Notes:
- Use `--session "$path"` (explicit file) so the parent knows the exact path without parsing the
  header. Do **not** pre-create the file: pi creates it on the first assistant message
  (0.85.1 source). An existing empty file breaks `openSync(...,"wx")`.
- `--mode json -p` is the 1.4.0 subagent's own choice (`index.ts:298`). It gives the event
  stream **and** the session file. `-p` makes it one-shot.
- Omit `--tools` when the role has none, so Pi uses the default selection
  (pi-1.4.0 `cli.md:128`).
- `--thinking` is only valid for a model that supports it; Pi clamps it (pi-1.4.0 `cli.md:69`).
- `--append-system-prompt <file>` is repeatable (pi-1.4.0 `cli.md:231`). Use a 0600 temp file
  like the subagent example (`index.ts:237-245`) so the prompt does not leak into argv/scrollback.
- Do **not** add `--close-on-exit`; keep the pane so a human can attach and read it
  (repo convention). If you want auto-close, add it and accept the lost scrollback.
- Avoid `-x` on the pane shell for this command, or a secret in a literal arg leaks into the
  scrollback (SKILL.md:209-213). Use env vars or files.

### B. Parent collect loop

```
spawn pane -> get pane_id (terminal_<id>)
wait for run_dir/exit with a startup deadline (15s) and a run deadline (configurable)
  - deadline hit before any output: read run_dir/stderr, report spawn failure
read session_file:
  - absent => fail "no assistant message"
  - drop a torn final line, parse the rest
extract last assistant text (jq in section 3)
attach usage: .message.usage {input,output,cacheRead,cacheWrite,totalTokens,cost}
cap the returned text (see token section); always write the full text to run_dir/answer.md
return {role, model, text, usage, stopReason, exit, session_file}
```

- The **exit marker** is the completion signal, not `dump-screen` and not a `sleep` loop
  (SKILL.md:170-171). Reuse `_watch_pane` / `_pane_done` (`zellij-llm.sh:203-286`).
- Read the file **after** the marker exists, so no rewrite window is open.
- Cap the text the parent inserts into its own context. A 50 KB cap (the 1.4.0 subagent's
  `PER_TASK_OUTPUT_CAP`, `index.ts:37`) is ~12.5k tokens per child. For a fan-out of 8 that is
  ~100k tokens into the parent, so use a smaller cap (for example 8 KB ≈ 2k tokens) and keep
  the file path for the rest.

### C. Stop path when the child ignores SIGTERM

zellij gives no direct signal to the child. Escalate by pane:

```bash
# 1. polite: interrupt the foreground process in the pane
zellij action send-keys -p "$pane_id" 'Ctrl c'
sleep 2
# 2. close the pane (kills its PTY child)
zellij action close-pane -p "$pane_id"
# 3. verify and, if the session is only ours, tear it down
zellij action list-panes --json --all -s | jq -e --arg id "$id" \
  '[.[] | select(.is_plugin==false) | select((.id|tostring)==$id)] | length==0'
zellij kill-session "$session"   # only when this pane was the last user
```

- Write a `run_dir/stopped` file so `wait` returns `EXIT:130` rather than hanging.
- `close-pane` kills the pty; if the pi process spawned children, also `kill-session`
  (SKILL.md:14, 290). Do not run `kill-session` on the user's session.
- The session file stays resumable (loader skips a torn line), so a stopped run can be resumed
  with `pi --session <file>`.

### D. `zellij-llm pi` command group

Mirror `zellij-llm opencode` (`zellij-llm.sh:517-655`, `done.md`): argc `parent::child`
functions, shared `_session_name`, `_ensure_session`, `_cmd_dir`, `_new_cmd_id`,
`_resolve_pane_ref`, `_watch_pane`, and the exit-marker convention.

| Command | Behaviour |
|---|---|
| `pi spawn` | Start one sub-agent in a pane. Flags: `--pane <slug>`, `--role <name>`, `--task <text>`, `--model`, `--thinking`, `--tools`, `--append-system-prompt` (repeatable), `--session-file <path>` (default `<run-dir>/pi.jsonl`), `--cwd`, `--wait`, `--mode stream\|heartbeat`, `--dry-run`. Prints `spawned pane '<pane>' in session '<name>' (run <id>, session <file>)`. |
| `pi send` | Type a follow-up into a running pane (long-lived worker). `--text`, `--no-submit`. Uses `write-chars` + `write 13`. |
| `pi watch` | Follow a pane to its exit marker, then print `EXIT:<code>` and the extracted answer. Modes as today. |
| `pi list` | Table of panes: pane id, title, role, exited, exit_status, session file, and whether an answer was extracted. |
| `pi attach` | Print `zellij attach %q <session>` (same as `opencode::attach`). |

- Reuse the naming convention `llm:<repo-slug>:<llm-session-id>[:<slug>...]` and pane slug
  `<role>-<slug>` (SKILL.md:215-240). Do not invent a new scheme.
- Reuse the run directory `<cache-root>/<pane>/<cmd-id>/` with `exit`, `events.jsonl`,
  `stderr`, `answer.md` (`zellij-llm.sh:382-412`).
- `pi spawn --dry-run` prints the exact `pi ...` argv (like `opencode spawn --dry-run`).
- Keep `pi spawn` single-pane. A fan-out is a shell loop over roles, each with its own
  `--session-file` and its own run dir.

### E. Token consequence: fan-out versus one persistent worker

A pane child is a **fresh process**. It re-reads every time:

- the Pi system prompt (preamble + tools + cwd) — order 2–3k tokens;
- discovered context files (`AGENTS.md`, `CLAUDE.md`) unless `--no-context-files` — this repo's
  `AGENTS.md` is **9,450 bytes ≈ 2.4k tokens**; nested `AGENTS.md` files add more;
- the skill index (6 skills, `.agents/skills/*/SKILL.md` total 57,394 bytes ≈ 14k tokens if
  all bodies load; only descriptions load by default — **unverified** exact selection).

Take **≈6k input tokens of pure overhead per child** (system prompt + AGENTS.md + skill index;
measure with `pi --mode json` and read `usage.input` of the first assistant message).

| Case | Overhead input tokens | Notes |
|---|---|---|
| Fan-out of N=8 panes | **≈48k** | before any task text or tool output |
| Same 8 tasks, one persistent worker | **≈6k once** | later runs re-send history; prompt caching turns most of it into cheap `cacheRead` (see `usage.cacheRead`) |
| Returned text into the parent | 8 × cap | a 50 KB cap is ~12.5k tokens each (~100k); an 8 KB cap is ~2k each (~16k) |

So a fan-out of 8 costs roughly **8× the fixed prompt cost** and adds every child's result to
the parent's context. Two mitigations: pass `--no-context-files` and a minimal
`--append-system-prompt` for narrow roles (scout), and use one persistent `pi send` worker for
sequential tasks. Use a fan-out only when the tasks are genuinely parallel and isolated.

---

## Spike sketch (no cost, no pane in the user's session)

```bash
# 0. isolated session, no token spend:
export ZELLIJ_SOCKET_DIR=/tmp/pi-spike
S=pi-spike; zellij attach --create-background "$S" >/dev/null 2>&1 || true

# 1. prove the session-file shape with a fake "pi" that writes JSONL (no model):
mkdir -p /tmp/pi-spike-run
cat >/tmp/fake-pi <<'EOF'
#!/usr/bin/env bash
# emit a minimal v3 session: header, system, user, assistant-with-text
printf '%s\n' \
 '{"type":"session","version":3,"id":"u","timestamp":"t","cwd":"/x"}' \
 '{"type":"message","id":"a","parentId":null,"timestamp":"t","message":{"role":"user","content":"hi","timestamp":1}}' \
 '{"type":"message","id":"b","parentId":"a","timestamp":"t","message":{"role":"assistant","content":[{"type":"text","text":"ANSWER"}],"stopReason":"stop","model":"m","usage":{"input":10,"output":2,"totalTokens":12}}}' \
 >"$1"
printf 0 >"$2"
EOF
chmod +x /tmp/fake-pi
bash -c '/tmp/fake-pi /tmp/pi-spike-run/pi.jsonl /tmp/pi-spike-run/exit'

# 2. extraction check:
jq -rs '[ .[] | select(.type=="message" and .message.role=="assistant")
          | .message.content[]? | select(.type=="text") | .text ] | last' \
   /tmp/pi-spike-run/pi.jsonl      # => ANSWER

# 3. one real, cheap round-trip (costs tokens; run only when approved):
zellij-llm pi spawn --session pi-spike --pane scout-smoke --role scout \
  --task 'reply with the single word OK' --model <cheap-model> --wait --mode heartbeat
# expect: EXIT:0 then the extracted text "OK" and a usage block.

# 4. failure path (should fail in under a second):
zellij-llm pi spawn --session pi-spike --pane bad-model --task x \
  --model no/such-model --wait        # expect EXIT:!=0 within the startup deadline
```

## Open items (marked unverified)

1. 1.4.0 session write path: assumed the same `appendFileSync` / "no file until first assistant"
   behaviour as 0.85.1.
2. Pane environment inheritance: assumed server environment, not caller.
3. Non-TTY behaviour when several providers match a fuzzy `--model`.
4. Exact default skill/context token selection; measure the first assistant `usage.input`.
5. `agent_settled` presence before 1.4.0 (0.85.1 `json.md` shows only `agent_end`).


