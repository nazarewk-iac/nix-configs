---
type: Research
description: How to isolate a Pi agent in this homelab, how it can safely manage other machines, how a sub-agent becomes a zellij pane with a file as the result channel, and exactly which context files Pi reads.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T11:10:00+01:00
---

# Isolation, remote management, panes, and context files

Read from the Pi v1.4.0 docs (`security.md`, `containerization.md`,
`configuration.md`, `mcp.md`, `skills.md`, `sessions.md`), the v1.4.0 example
extensions, and this repository's own aspects. Where a claim comes from Pi's own
documents, it is quoted.

## 1. Pi's default posture is "same as your user", by design

`security.md`:

> Pi can read, change, and execute files with the permissions of the account that
> started it, and it does not ask for approval before every tool call.
> […] Watching the transcript, using project trust, and reviewing changes do not
> create a security boundary.

And, on the working folder:

> The working folder controls resource discovery and the default location for
> tools, but it does not prevent commands from accessing other paths available to
> the Pi process.

So "run it in the repo" is not isolation. For a harness that manages other
machines with SSH, this is the first decision, not a later hardening step.

## 2. Isolation options, and which ones this homelab already has

Pi documents four routes. Mapped onto what exists here:

| Pi's route                          | What it isolates                                                   | Homelab equivalent, today                                                                                                                                                                  |
| ----------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Dedicated OS user                   | anything that user cannot reach                                    | `kdn.users` rows + a systemd unit. Cheapest. Still shares the kernel, the network, and any group the user is in.                                                                           |
| Plain Docker (whole process)        | Pi, its tools, its extensions                                      | `kdn.virt-containers.docker` / `.podman` aspects. Needs the repo bind-mounted, and a credential strategy.                                                                                  |
| Docker Sandboxes / **OpenShell**    | same, with **policy-controlled credentials and inference routing** | `pkgs.openshell` is in the pinned nixpkgs (`0.0.116`). Notable: it is the only documented option that keeps provider credentials out of the sandbox and routes inference through a policy. |
| **Gondolin** extension (tools only) | only the built-in tools and `!` commands, in a local micro-VM      | `kdn.virt-microvm.host` (microvm.nix) already exists; Gondolin itself is an example extension in the Pi tree, not in nixpkgs.                                                              |
| **bubblewrap sandbox extension**    | per-command filesystem and network policy                          | nixpkgs has `bubblewrap` and `socat`; the extension is `examples/extensions/sandbox/index.ts` and uses `@anthropic-ai/sandbox-runtime`                                                     |

The sandbox extension is the pragmatic middle ground, and its config is exactly
the shape this problem needs:

```json
{
  "enabled": true,
  "network": { "allowedDomains": ["github.com", "*.github.com"], "deniedDomains": [] },
  "filesystem": {
    "denyRead": ["~/.ssh", "~/.aws"],
    "allowWrite": [".", "/tmp"],
    "denyWrite": [".env"]
  }
}
```

It overrides the built-in `bash` tool with a `spawn` through bwrap, so every
generated command is bounded while the rest of Pi stays on the host. Its cost is
that extension tools (including a delegation tool we write) run **outside** the
boundary unless they delegate their own work — Pi says so plainly:

> When host Pi delegates built-in tools through Gondolin, other extension tools
> still run on the host unless they also delegate their work.

### Recommendation

Two tiers, both cheap here:

1. **Every run:** a dedicated unprivileged user (`kdn.users.<agent>`), a narrow
   home, and the bubblewrap sandbox extension: `denyRead ~/.ssh`, `allowWrite` the
   repo and `/tmp`, and an allow-list of network destinations (the `brys` proxy and
   the KVM address).
2. **Untrusted or long runs:** a disposable microVM through
   `kdn.virt-microvm.host`, or OpenShell if the credential proxy earns its keep.
   The microVM route has a real cost: it needs the flake, a TAP interface, and a
   boot per run, and a 16 GB host cannot afford many.

Do **not** use "the transcript is watched" as a control. Pi's security page rules
it out explicitly.

## 3. Managing other machines without handing over a skeleton key

The risk is concrete: an agent with `~/.ssh/id_ed25519` and `known_hosts` can
reach every host the owner can.

What the repository already provides, and why it fits Pi's own advice ("use
narrowly scoped, short-lived credentials"):

| Primitive                                                          | What it gives                                                                                                          |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| SSH CA + `kdn-certs ssh login <host>`                              | a **short-lived user certificate with explicit principals**, signed after a YubiKey touch. Nothing long-lived on disk. |
| `kdn.ssh-access` (`kdn-*` dispatcher)                              | one entry point per host, with the connectivity graph, instead of ad-hoc addresses.                                    |
| Per-host `kdn.hw.nanokvm` + the KVM MCP key at `/etc/kvm/mcp.json` | out-of-band access, keyed per device.                                                                                  |
| NetBird                                                            | transport, if a host is off-LAN. Not a credential.                                                                     |

The design that follows:

- the agent host holds **no** long-lived SSH private key; a wrapper obtains a
  certificate per host or per run and puts it under a temp `SSH_AUTH_SOCK`-style
  path that the sandbox allows;
- the sandbox denies `~/.ssh` and `~/.config/age`, so a prompt injection cannot
  read them;
- the delegation tool takes a **host name**, never an address, and the wrapper
  refuses a host that is not in the topology data.

## 4. Sub-agents as zellij panes: the reference implementation, and the variant you want

The example extension (`examples/extensions/subagent/index.ts`, 1036 lines) is the
shape to copy. Its dispatch is:

```ts
const args: string[] = ["--mode", "json", "-p", "--no-session"];
if (model) args.push("--model", model);
if (inheritsDispatchConfig && dispatchDefaults.thinkingLevel) args.push("--thinking", …);
if (agent.tools?.length) args.push("--tools", agent.tools.join(","));
if (agent.systemPrompt.trim()) args.push("--append-system-prompt", tmpPromptPath);
args.push(`Task: ${task}`);
const proc = spawn(invocation.command, invocation.args, { cwd, shell: false, stdio: ["ignore", "pipe", "pipe"] });
```

with agent definitions in Markdown files carrying frontmatter
(`name`, `description`, `tools`, `model`) — the same shape as our
`.agents/skills`. It supports single, parallel (max 8 tasks, 4 concurrent) and
chain mode with a `{previous}` placeholder, and it tallies turns, tokens, cost and
context per agent.

Its weakness for this repository: stdio is piped, so the child is invisible. You
cannot watch it, attach to it, or interrogate it while it runs. The watch loop in
[../gaz-den-workstation/design.md](../gaz-den-workstation/design.md) exists
precisely because invisible children are how a run dies quietly.

**The pane variant, which needs no new plumbing, because Pi sessions are files:**

```sh
zellij action new-pane --name "pi-$agent-$id" -- pi \
  --session "$state/$agent-$id.jsonl" \
  --model "brys/$alias" --thinking "$level" --tools "$tools" \
  --append-system-prompt "$prompt_file" \
  -- "Task: $task"
```

- the human (or the overseer) attaches to that pane with `zellij attach`, watches
  the real TUI, and types into it if needed — no TUI emulation required;
- the **result channel is the session file**, not stdout. When the child exits,
  the parent reads the last assistant message from
  `$state/$agent-$id.jsonl` (or runs `pi --export` for an HTML artifact);
- `store(key, value)` style state is unnecessary: the file _is_ the state, and a
  crashed child still leaves a partial transcript;
- killing a pane is `zellij action close-pane`, which is the natural stop button;
- `zellij-llm` (`packages/llm/zellij-llm`) already has the session/pane
  conventions, the run marker and `opencode watch`; a `zellij-llm pi` group is a
  small addition in the same style.

Two consequences worth stating up front:

1. **The concurrency cap must come from the fleet, not from Pi.** The example
   allows 4 concurrent children. On `brys` the honest number today is roughly
   2–3 co-resident models (see
   [../llama-swap-concurrency/sets.research.md](../llama-swap-concurrency/sets.research.md)),
   and several aliases are the same process. Four panes that all resolve to
   `qwen3.5-4b` are a queue with four windows open.
2. **A pane is not a boundary.** Pi runs with the user's permissions in that pane.
   Isolation still has to come from §2.

## 5. Context files: what Pi reads, verified

From `configuration.md`:

> Context files are separate from project `.pi` configuration. Pi loads them from
> the agent directory, the working directory, and its parent directories. A
> context file applies whenever Pi runs in its directory or anywhere below it.

- Recognised names: `AGENTS.override.md`, `AGENTS.md`, `AGENTS.MD`, `CLAUDE.md`,
  `CLAUDE.MD`.
- `AGENTS.override.md` replaces `AGENTS.md`/`CLAUDE.md` **in the same directory
  only**; it does not suppress an ancestor's file.
- They load **regardless of project trust** — so treat a repo's `AGENTS.md` as
  untrusted input when the repo is untrusted.
- `--no-context-files` (`-nc`) disables discovery.
- `--approve` / `--no-approve` control project-local trust per run.

And, importantly for this repository, from `security.md` — the trust-protected
resource list includes:

> project `.agents/skills` in the current directory or an ancestor directory

So Pi reads **our `.agents/skills/` layout natively**, with the same trust rule as
`.pi/`. That means the `kdn-llms`, `zellij`, `jujutsu-vcs` and `nanokvm` skills can
serve both harnesses from one place. Our `.agents/rules/*.md` are **not**
discovered automatically; they are reached only because `AGENTS.md` links them, so
a Pi agent gets them only if it follows the links.

Practical consequence: a harness directory should carry its own small
`AGENTS.md` (what this run is, what it may touch, what it must never do) instead
of relying on the repository-wide one, which is written for a different job.

## 6. What is missing and must be built

| Gap                             | Why it matters                                                                  | Cheapest shape                                                                                                     |
| ------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| A `tools`-style delegation tool | Pi has none built in                                                            | copy the example, change the spawn to a zellij pane, read the session file for the result                          |
| Alias → model mapping           | `--model` needs `provider/id`; our aliases live in `hosts/brys/llm-routers.nix` | generate `<agent-dir>/models.json` (compatible endpoint) or a `--model brys/<alias>` pattern, from the router data |
| Fleet-aware concurrency         | Pi's default of 4 exceeds what one box serves                                   | a cap derived from `kdn.llm.local.swap.coResidentTiers`, plus an admission check before dispatch                   |
| Supervision                     | invisible children loop                                                         | the pane + the existing watch loop and thresholds                                                                  |
| Per-agent accounting            | the evaluation needs cost and tokens per role                                   | the session file has usage; aggregate it, as the example does                                                      |
| A stop condition                | a child that loops costs hours at 2.5 t/s                                       | wall-clock and turn caps per role, enforced by the dispatcher, not the prompt                                      |
| Credential scoping              | see §3                                                                          | CA-signed short-lived certs; `denyRead ~/.ssh`                                                                     |

## 7. Personas, mapped onto Pi

The four roles from the host tasks map cleanly, with one addition:

| Role                   | Pi shape                                                                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Owner                  | the human; presses power, answers the usability questions, approves the sandbox profile once                                                                                                                              |
| Overseer               | a separate Pi process with `--tools read` and the host's supervision skills, driving panes and reading session files. It should not be able to edit.                                                                      |
| Orchestrator           | the interactive pane, `--model brys/orchestrate-deep-slow --thinking high`, with the delegation tool                                                                                                                      |
| Workers                | headless panes, small aliases, `--tools` narrowed per role                                                                                                                                                                |
| **Architect/reviewer** | a pane with `--tools read,grep,find,ls` and a **`--fork` of the orchestrator's session**, so it sees the real transcript instead of a pasted summary. This is the one role Pi does materially better than opencode today. |

## 8. Not verified

- Whether `openshell` 0.0.116 in nixpkgs actually runs the policy gateway the docs
  describe; it has not been tried here.
- Whether the bubblewrap sandbox extension works with a NixOS `bubblewrap` (the
  example assumes a distro path and `socat`).
- Whether a Pi child in a zellij pane exits reliably when the parent aborts
  (`close-pane` sends SIGHUP; the example uses `proc.kill`).
- Whether `--fork` of a session is safe while the parent is still writing it.
- Whether our repo's `.agents/skills` load under a _declined_ trust decision — the
  doc lists them as trust-protected, so a headless run likely needs `--approve`
  or a user-level copy.
