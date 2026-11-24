# Working with local LLMs in this repository

This is the default way of working for every Pi session in this repository. It is appended to the
system prompt by the Pi wrapper (`devenv.nix`), so a plain `pi` already follows it.

Read the repository's own `AGENTS.md`, `CLAUDE.md` and the relevant `.agents/skills/*` first. This
file only adds the multi-model working style on top.

## Delegation is the default, not an option

Local models are cheap and fast; your own context is the expensive resource. So:

- **Recon goes to a sub-agent.** Never hand-read more than two files to find something. Send a
  `scout` through `delegate`, and batch independent lookups into ONE `delegate` call with `tasks`.
- **Verification goes to a sub-agent** (`reviewer`) when a change is subtle.
- **Mechanical edits go to a sub-agent** (`worker`) with ONE exact task per call: "rewrite
  attribute X to Y", not "improve the config". A vague task to a fast model fails confidently.
- **Hard reasoning goes to a sub-agent** (`planner`) before a multi-step change.
- **Open questions go to a sub-agent** (`consultant`) when you need options, not an answer: a
  design fork, an approach that is not working, a feature to size. It brainstorms several
  directions and recommends one; it changes nothing.
- **Name the model id, and prefer `qfn`.** The purpose aliases are gone: a model is its id
  (`qfn`, `lfm2.5-24b-a2b`, `mellum-2.1-12b-a2.5b-thinking`, ...). Pass
  `model:"litellm/<id>"` per task when you want a specific one; otherwise the agent's default
  applies. `qfn` is the frontier: always loaded, never switches, and its slot count is the
  concurrency limit (5 on the resting profile), so a sixth concurrent call queues rather than
  fails. Every other local model needs a colo profile and is refused on the resting one.
- **Bound your own recon.** If you have made five tool calls without an edit or a delegate, stop
  and delegate the rest.
- **One response has a hard output budget.** The model's advertised `maxTokens` caps a single turn,
  and a reasoning model's thinking comes out of that same number. When the model reaches it the
  turn fails with a length error; it is not silently shortened. Write a long report to a file and
  reply with the path, or split the work across delegate calls.

A sub-agent's "done" is a claim, not a fact. Verify every result yourself with the cheapest
mechanical check that proves it (`nix-instantiate --parse`, `nix eval`, a `rg` for the expected
text). Local models corrupt structured files often.

## Keep changes small and attributable

- Commit each self-contained change with `jj` as you go, then `jj new`. Never push.
- Never leave `@` carrying a description: the next edit would silently join it.
- Report at the end of a turn: what changed, what you verified and how, what remains, and every
  decision you made without asking.

## ClankTalk sessions

When the `clank_talk` tool is available and the other tools are hidden, use `clank_talk` for all
work: reading, editing, search, jj, Nix and tests. The delegation rules above do not apply in that
session; the policy defines the only tools. If a task needs a tool that `AGENTS.talk` does not
define, stop and tell the human. See [docs/clank-talk.md](../../docs/clank-talk.md).

## When a decision is not yours

Some actions belong to the owner: hardware, reboots, installs, disk or secret operations, and
anything that erases data. Prepare the repository change, then write the hand-off in the task's
`.worklog.md` and stop. Do not guess.
