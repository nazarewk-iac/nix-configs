---
type: Rule
description: "Attribute every agent-assisted jj change with kdn-jj-meta; Assisted-by is the disclosure, Co-authored-by is optional and never the human."
timestamp: 2026-11-16T09:35:00+01:00
---

# jj attribution with `kdn-jj-meta`

Full doc: [docs/kdn-jj-meta.md](../../docs/kdn-jj-meta.md). The tool lives in
[`packages/kdn-jj-meta/`](../../packages/kdn-jj-meta/).

**Every agent-assisted change carries `Assisted-by:`.** Before you finish a commit, run:

```sh
kdn-jj-meta attribute <change-id> --harness <name> --model <model>
```

The tool reads the harness, session and model from the environment when you omit the flags, so the
usual call is:

```sh
kdn-jj-meta attribute <change-id>
```

- The default profiles are `agent`, `nixpkgs` and `asf`: the tool writes `Assisted-by`,
  `Generated-by`, `Session-Id`, `Harness` and `Model` together. Narrow the set with
  `--profile nixpkgs` when a human materially revised the work, or `--profile asf` when it is
  mostly machine-authored.
- `Assisted-by: <harness>:<model>` is the disclosure the Nixpkgs transparency policy requires.
  `Co-authored-by:` does **not** satisfy that policy.
- `Session-Id:` and `Harness:` tie the change to the agent session. `kdn-journal` reads them back.
- Never add `Co-authored-by:` for the human author. The human is already the author. If a project
  wants the GitHub convention, the co-author is the agent and it needs an explicit agent email:
  `kdn-jj-meta attribute <id> --profile github --coauthor-email <email>`.
- Never add `Signed-off-by:` on behalf of an agent. That is the human's DCO certification.
- Never delete or rewrite an existing trailer. The tool appends only missing lines; keep it that
  way.
- Attribute only a **mutable** change. The tool refuses immutable history by default.
- Do **not** attribute the unnamed empty `@` at the tip. Attribute the described change you just
  created.
- `kdn-jj-meta check --revset 'main..@'` is the gate before a push. jj has no commit-msg hook, so the
  gate is a command, not a hook.

`kdn-journal` calls the same binary when it records a change. Do not duplicate the trailer policy
in another tool or in a hand-written commit message.

The binary embeds this skill. `kdn-jj-meta skill` prints it, and `kdn-jj-meta skill --dir <path>`
installs it as `<path>/kdn-jj-meta/SKILL.md`. Home Manager links it into `~/.agents/skills`,
`~/.config/opencode/skills` and `~/.pi/agent/skills`, so the same instructions reach an agent in any
repository.
