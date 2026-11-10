---
type: Task
description: Integrate numtide/llm-agents.nix as the primary source of LLM and agent tooling, and deduplicate the flake inputs it shares with this tree.
status: open
authored_by: agent
timestamp: 2026-11-10T10:30:00+01:00
---

# Integrate numtide/llm-agents.nix

Upstream: <https://github.com/numtide/llm-agents.nix>

Related collection to consult: <https://github.com/rytswd/pi-agent-extensions> — a curated list of Pi
agent extensions. Use it for overlap analysis (which of our vendored extensions already exist there)
and as a source of ideas for missing capability, before writing another local extension.

## Problem

This repository vendors or wraps several LLM and agent tools by hand:

- `packages/pi-coding-agent` — a vendored `pi-coding-agent` with a hand-maintained version,
  `src`/`npmDepsHash`/`modelData` hashes, and an overlay that picks between the local copy, the
  `pi` flake input, and nixpkgs;
- `packages/pi-coding-agent-extensions` — hand-vendored Pi extensions (`pi-btw`, `pi-orchestrator`,
  `fleet-status`, `model-discovery`, ...);
- `packages/llm` — a hand-written `zellij-llm` and the LLM CLI helpers;
- `packages/opencode-compat-proxy` — a local shim for the OpenCode compat endpoint;
- assorted tool pins in `flake.nix` (`oh-my-pi`, `devenv` overlays, ...).

Each of these needs a manual bump and a hash refresh, and each one duplicates a transitive input
that the rest of the tree already follows sometimes only by accident.

`llm-agents.nix` is a curated flake that packages this class of tool from a single source, with
its own `nixpkgs` and a consistent set of `follows`. It should be treated as the **higher-priority
source** for LLM and agent tooling: above `nixpkgs`, above a hand-vendored copy, and above searching
the internet for a package or writing a wrapper.

## Goal

1. **One source.** Where `llm-agents.nix` provides a tool, take it from there instead of vendoring
   or wrapping it locally.
2. **Keep the shims.** A local package may stay as a thin shim (same name, same options) so that
   consumers and host modules do not change. The shim calls the `llm-agents.nix` package.
3. **Deduplicate inputs.** Add `inputs.llm-agents.inputs.<dep>.follows` for every dependency this
   tree already pins, and re-run `hack/flake-structure-analysis.py` to prove no duplicates remain.
   Prefer following `nixpkgs` and the shared toolchain over letting the new input bring its own.
4. **One version knob.** A bump of the `llm-agents.nix` input should move every tool it provides.
   An exception needs a written reason in the module that pins it.
5. **Prove it.** A host build, `devenv shell`, `opencode plugin list`/`opencode models`, and
   `pi --version`/`pi --list-models` are the acceptance checks. See
   [docs/post-change-checks.md](../../../post-change-checks.md).

## Candidate integrations

From `rytswd/pi-agent-extensions`, worth evaluating against our vendored set:

- **inbox** — a per-session Unix socket (`$PI_INBOX`) that lets a tool subprocess push an event into
  the conversation asynchronously. Fits the fleet/harness work: a long build or a watcher can wake
  the agent instead of polling.
- **python** — a persistent Python interpreter tool. State survives between calls, so an agent can
  load a CSV once and keep working on it.
- **fetch** — an HTTP request tool that does not need `bash`/`curl`. A narrower, approval-friendly
  substitute for shelling out, and a natural fit for the sandboxed MCP/tooling direction.
- **permission-gate** — prompts on dangerous bash commands (`rm -r`, `git push -f`) and can hard-block
  whole-tree `find`/`rg` scans, with `/gate list`. Compare with the OpenCode permission baseline and
  the `pi` approval flow before adding a third policy layer.
- **notify** — a desktop notification when the agent finishes, toggled with `/notify`.

Overlap to resolve before adding any of them: `questionnaire` (we have `pi-ask-user`), `statusline`
(we have `fleet-status` and `pi-atelier`), `direnv` (devenv provides the environment) and `stash`
(editor-only). Do not vendor a second copy of something the tree already ships.

## Scope

In scope:

- `flake.nix` — the new input and its `follows`;
- `packages/pi-coding-agent` and its overlay selection;
- `packages/pi-coding-agent-extensions` — decide per extension: take upstream from
  `llm-agents.nix` or from `rytswd/pi-agent-extensions` if it is there, else keep the vendored copy;
- `packages/llm` (`zellij-llm`) and `packages/opencode-compat-proxy` — consider replacing;
- the devshell wrappers in `devenv.nix` and the den aspects that name a tool
  (`dev-llm-*`, `pi-client`, `opencode`);
- `hack/flake-structure-analysis.py` follow-up output.

Out of scope:

- The LLM server side (`modules/den/aspects/llm.nix`, llama-swap, the fleet data model).
- Renaming user-facing commands or options. The shim keeps them.

## Acceptance

- `nix eval .#nixosConfigurations.oams.config.system.build.toplevel.drvPath` succeeds, and every
  host the toolset reaches builds.
- `devenv shell -- true` exits 0.
- `pi --version` is the version `llm-agents.nix` provides, `pi --list-models` still shows the fleet,
  and `opencode plugin list` / `opencode models` are unchanged.
- `hack/flake-structure-analysis.py` reports no missing `follows` for the repositories the new
  input pulls in.
- The vendored copies that were replaced are either deleted or reduced to a shim with a comment
  naming `llm-agents.nix` as the source.

## Risks

- `llm-agents.nix` may lag or lead the versions this tree tested. A bump of that input is then a
  tool bump, not a no-op; keep the acceptance checks in the loop.
- Following `nixpkgs` from `llm-agents.nix` can break a tool that expects a specific patch set. The
  fallback is to let that one dependency float and document why.
- The hand-vendored Pi extensions may carry local patches (`PATCHED`, `passthru.patches`). Do not
  drop them silently; port the patch to the `llm-agents.nix` package or keep the vendored copy.

## Follow-up

After the first host is green, add the same route to the remaining hosts and remove the now-unused
`src`/`npmDepsHash`/`modelData` hashes from `packages/`.
