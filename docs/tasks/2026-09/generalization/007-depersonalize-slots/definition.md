---
type: Task
description: Lift the creator's personal defaults, provider choices, and opinions out of shared slot options so an adopter gets a neutral baseline.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 007 — de-personalize slots

Hub: [../generalization-plan.md](../definition.md). Depends on 001. Independent of the
006 direction decision — this improves slots whichever way 006 goes.

Goal: an adopter who enables a slot gets a neutral baseline, not the creator's setup.

Use **Pattern V1** (the drvPath equality gate) throughout. Every change here should be a no-op for
this repo's own hosts. A changed drvPath means a real behaviour change that needs justification.

## 1. Split the `requesty` provider into an opt-in sub-module

`modules/slots/opencode/default.nix` hardwires the commercial provider `requesty`:

| Line | Content |
|---|---|
| `:103` | `export REQUESTY_API_KEY="$(jq -r '.requesty.key // empty' …)"` |
| `:105` | a warning message that names requesty |
| `:140` | `provider.requesty = {};` in the default settings |

Move it into its own sub-module. An adopter does not have to enable that sub-module. An adopter who
enables `kdn.opencode` must not get a commercial provider by default.

Note that `modules/slots/llm/proxy/` already treats requesty correctly. It is one instance of a
general `instances.<name>` option with `upstreamUrl` (`:100`). Its README documents it by example.
Follow that pattern.

## 2. Lift the personal defaults out of shared options

| Option | File | Current default | Action |
|---|---|---|---|
| `kdn.jj.upstream.remote` | `modules/slots/jj/default.nix:31` | `"kdn"` | no default, or a neutral one |
| `kdn.jj.alwaysBlockedMessagePatterns` | `modules/slots/jj/default.nix:25` | `[ "scratchpad" ]` | empty default; see the note below |
| `"~/dev/**" = "allow"` | `modules/slots/opencode/default.nix:51,55,59,63,67` | 5 blocks | make the path an option |
| `kdn.llm` option examples | `modules/slots/llm/default.nix:432,450-451,462-463` | homelab FQDNs and overlay IPs | neutral examples |
| `KDN_LLM_API_KEY_<name>` | `modules/slots/llm/client/default.nix:39` | env-var contract carries the brand | decide: keep or parametrize |
| service unit names | several | hardcoded `kdn-` prefix | decide: keep or parametrize |

> **Care with `alwaysBlockedMessagePatterns`.** 001 fixes a bug where an empty pattern list
> silently disables a protective check. Change the default only after that fix lands, so an empty
> default fails loudly rather than quietly.

`modules/slots/ca/default.nix` (91 LOC) is the correctly parametrized exemplar — real `certFile`
and `keySopsFile` options, with the creator's own paths only in the docstring. Note that its
`example` at `:74-75` still shows `"${kdnConfig.self}/data/ca.pub"`. That is doc-only, and not a
rule violation. But it misleads a reader. Fix the example.

## 3. Make the two default-on slots side-effect free

| File | Line |
|---|---|
| `modules/slots/mcp/snoop/default.nix` | `:18` — `default = true` |
| `modules/slots/mcp/pretty-print/default.nix` | `:103` — `default = true` |

`.agents/rules/nix-conventions.md` states that all modules must be side-effect free by default.
These two break it. Flip them. Then set them explicitly in this repo's own `devenv.nix`, so
behaviour here does not change. Verify with Pattern V1.

## 4. Decide what a slot writes into the adopter repo

When an adopter enables `kdn.jj`, the slot installs `.agents/rules/jujutsu-vcs.md`, a jj-only
mandate, plus the fork-workflow docs. 5 slots read repo content through
`${inputs.nix-configs}/.agents/…`: `jj`, `jj/fork`, `nix`, `zellij`, `mcp/basic-memory`.

This is not automatically wrong — an adopter may want the rules. But it must be a choice. Add an
option to opt out of the shipped agent rules. Default it so an adopter does not silently receive
the creator's own rules.

Every `files` block already reads `config.kdn.isSourceRepo`, which the loader declares rather than
the slot. Keep that.

## 5. Move `kdn-graph.nix` out of the slots tree

`modules/slots/ssh-access/kdn-graph.nix` is 176 LOC of the creator's hosts, LAN and management IPs
(`192.168.41/73/252.*`), WAN ports, `*.kdn.im` zones, and literal addresses.

The mechanism is sound, and its header documents it. It uses a `kdn-` prefix. The loader does not
pick it up, because the loader reads only `*/default.nix`. A host imports it explicitly from its
`mkSlots` call. **The location is wrong** — personal data belongs in the single folder from
[009](../009-personal-data-folder/definition.md).

Two actions here:

1. Coordinate the move with 009. Do not invent a second location.
2. **Write the pattern down.** Today it exists only in that one file's header. An adopter needs to
   know how to supply their own graph.

## 6. Do not do these

- **Do not rename the `kdn.*` namespace.** The churn buys nothing. Gap 10 in the hub.
- **Do not delete the `users` slot target.** It is unused today, and that is fine. Gap 11.

## Exit criteria

- Pattern V1: every host's drvPath is unchanged, or the `.done.md` justifies each change.
- Pattern V3: a scratch adopter flake enables `kdn.opencode` and gets **no** commercial provider.
- The standalone check from 001 item 5 still passes.
- `nix run .#kdn-nix-fmt --` is clean.
