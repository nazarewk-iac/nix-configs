---
type: Guide
description: Day-to-day use of the Pi coding agent in this repository: choosing a model, resuming the last session, and naming sessions so they are findable instead of a hash.
timestamp: 2026-11-01T17:15:00+01:00
authored_by: agent
---

# Pi harness

Pi is the second coding agent in this repository, beside OpenCode. This page covers the daily
loop: pick a model, resume where you left off, and name sessions so you can find them later.

The repo owns Pi's configuration (`data/pi/`, wired in `devenv.nix`), so a plain `pi` inside
`devenv shell` already has the fleet models, the extensions and the agents. Nothing lives in
`~/.pi` except history and credentials.

## 1. Discover and select models

```bash
pi --list-models                    # every model, with context and max-output columns
pi --list-models qwen               # fuzzy search; no network
pi --list-models --provider brys    # one provider only
```

The columns are `provider model context max-out thinking images`. `context` is a **client budget**,
not the served maximum: `data/llm.nix` caps it (384k by default) so a session cannot grow to a
model's full window.

Pick a model per run with `--model`:

```bash
pi --model brys/code-std-fast                    # a stable purpose alias
pi --model brys/qwen3.8-flash-next --thinking high   # frontier + depth
pi --model brys/qwen3.8-flash-next-longest       # the 1M-context tier
```

Use an **alias** (`chat-std-fast`, `code-deep-slow`), not a base model id: the server decides
which model serves that intent, so an alias keeps working when the fleet changes. Inside a
session, `/model` opens the picker and `/thinking` sets the depth; `Ctrl+P` cycles the models
named by `--models`.

Which alias to use, and what each purpose means, is the `kdn-llms` skill. The short version:
`dumb`/`quick` for mechanical work, `std` for normal, `deep` only when it is genuinely hard.

## 2. Resume the last session

```bash
pi -c                     # continue the most recent session for this directory
pi --resume               # pick from a list
pi --session 01a193a9     # a specific session by partial UUID
pi --fork 01a193a9        # branch a copy, leaving the original untouched
```

`-c` (`--continue`) is the low-effort one: it takes the newest session whose working directory is
the current one, so run it from the repo root.

**Partial UUIDs work** — `--session` accepts any unambiguous prefix of the id. The id is the
second half of the session filename, after the timestamp:

```
~/.pi/agent/sessions/--home-kdn-...-nix-configs--/2026-10-31T20-31-47-192Z_01a193a9-47f7-....jsonl
                                                    └── timestamp ──┘ └──── session id ────┘
```

Two behaviours worth knowing:

- **Resume replays history, not configuration.** Extensions, `models.json` and the system prompt
  are read at startup. So resuming an old session keeps that session's transcript, and a system
  prompt you changed since then does **not** apply to it. For a behaviour change, start a new
  session.
- **`--fork` is the safe branch.** It copies the history into a new session, so the original stays
  intact while you take the work in a different direction.

Sessions are plain JSONL files under `~/.pi/agent/sessions/--<cwd>--/`. They are user data: never
commit them.

## 3. Name sessions

A UUID is not memorable, so give the session a name when you start it:

```bash
pi --name 'pryll-den-port'    # or: pi -n pryll-den-port
```

The name is stored as a `session_info` entry in the session file (not on the header line), and it
shows in `--resume` and in `/sessions`. A fork copies the history but not the name, so pass
`--name` again when you fork. You can also rename a live session with `/name <name>`, or over RPC with
`set_session_name`.

### Listing sessions, so you never need the hash

There is no `pi sessions` subcommand, so use the files. The name, id and working directory are in
the first line of each session file:

```bash
# name, id, and start time for every session in this repository, newest first.
# The name is a separate `session_info` entry, not a field on the header line, so read the LAST
# one; the header is the fallback for an unnamed session.
for f in $(ls -t ~/.pi/agent/sessions/--home-kdn-dev-github.com-nazarewk-iac-nix-configs--/*.jsonl); do
  jq -rs '([.[]|select(.type=="session_info")|.name]|last) // .[0].name // "-"
          as $n | [$n, .[0].id, .[0].timestamp] | @tsv' "$f" 2>/dev/null
done | awk -F'\t' '{printf "%-22s %s  %s\n", $1, substr($2,1,8), $3}'
```

Measured output on this repository:

```
pryll-den-port         01a197b5  2026-11-01T15:23:23.817Z
-                      01a193a9  2026-10-31T20:31:47.192Z
```

Then resume by what you read:

```bash
pi --session <id-prefix>
```

### Automating the name

Three options, cheapest first:

1. **Name it yourself.** `pi -n pryll-den-port`. One word, and it is the only one that is
   guaranteed to describe what you intended.
2. **Name it after the task directory.** A session that works on
   `docs/tasks/2026-10/pryll-mother-desktop/` is easy to name:
   `pi -n "$(basename "$PWD")"` is wrong for that, so use an explicit slug, or derive it from
   `jj` with `kdn-slug` (the same helper `zellij-llm` uses to name sessions).
3. **Rename after the first turn.** Start unnamed, then `/name pryll-den-port` once you know what
   the session turned into. This is the most accurate and costs one command.

What is **not** worth automating: deriving the name from the transcript. It reads well in
hindsight and badly at the time, and a wrong name is worse than a hash because it lies.

## Quick reference

| Task                             | Command                                      |
| -------------------------------- | -------------------------------------------- |
| list models                      | `pi --list-models [search]`                  |
| use a specific model             | `pi --model brys/<alias> --thinking <level>` |
| continue the newest session here | `pi -c`                                      |
| resume by partial id             | `pi --session <prefix>`                      |
| branch a session                 | `pi --fork <prefix>`                         |
| name at start                    | `pi -n <slug>`                               |
| rename live                      | `/name <slug>` inside Pi                     |
| set the model live               | `/model` (picker), `Ctrl+P` (cycle)          |
| set depth live                   | `/thinking`                                  |
| non-interactive one-shot         | `pi -p "..."`                                |
| export a transcript              | `pi --export out.html --session <prefix>`    |
| list the repo's agents           | `ls data/pi/agents/`                         |

## Related

- [kdn-llms skill](../.agents/skills/kdn-llms/SKILL.md) — which alias for which purpose.
- [docs/tasks/2026-10/pi-harness-multi-agent/](tasks/2026-10/pi-harness-multi-agent/definition.md)
  — the research and design behind the harness, including the subagent extension.
- `data/pi/` — the models, extensions and agents this repository owns.
