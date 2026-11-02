---
title: Central fleet LLM data model — solution
type: Reference
description: What shipped for the central fleet LLM data model, and the eval-diff that proves the server/client/member outputs are unchanged (except the intended appliance 320K fix).
timestamp: 2026-11-02T15:30:00+01:00
---

# Solution

`data/llm.nix` is now the single source of truth for the LLM fleet. It holds:

- `endpoints` and `pi` (unchanged).
- `servers.brys` — cross-model serving data: `package` (a named key), `defaultThreads`,
  `modelsDir`, `download`, `apiKeyDir`, `sessionStore`, the extra `routers` (`grunt`,
  `surveyed`), the resolved `swap` policy, and the two boot `profiles` (`desktop`,
  `appliance`).
- `models.<id>` — per model, host-agnostic identity (`aliases`, `capabilities`, `pi`,
  `vision`, `gpu`, `source`, native `contextSize`) plus `hosts.brys` serving data
  (`set`, `servedContext`, `common` = file/download/mmproj/draft/perf, and an optional
  `profiles.<p>.servedContext` delta).

`lib/llm.nix` exposes four projections: `mkServerModels data host profile`,
`mkPiModelsJson`, `mkCatalog`, and `mkMemberView data host`.

`hosts/brys/llm.nix` projects `mkServerModels` into `kdn.llm.local.models` and adds the two
host-only values (`package = pkgs.kdn.<key>`, the TLS `certs` path). `llm-config.nix` now
takes `profile` instead of a stack of feature flags; `default.nix` boots `desktop`,
`llms-frontier.nix` boots `appliance`. `hosts/brys/llm-routers.nix` is deleted.
`llm-agents.nix` and `oams` derive from `data/llm.nix` (non-`main`, enabled models).

## Verification (eval-diff)

Baselines were captured before the change and re-evaluated after, on
`nixosConfigurations.brys`:

| Output                                                                                 | Result                                                                                        |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `kdn.llm.local.models`, **desktop**                                                    | byte-identical to baseline                                                                    |
| `kdn.llm.local.models`, **appliance**                                                  | identical except `deepseek-v4-flash.perf.contextSize` 131072 → 327680 (the intended fix, R14) |
| `kdn.llm.local` `routers`/`swap`/`sessionStore`/`package`/`defaultThreads`/`modelsDir` | byte-identical                                                                                |
| `mkPiModelsJson`                                                                       | byte-identical                                                                                |
| `mkCatalog`                                                                            | byte-identical                                                                                |
| `llm-agents.nix` (sub-agents)                                                          | byte-identical (30 agents)                                                                    |

Commands (each was run for both profiles):

```sh
nix eval --impure --json --apply 'x: x.config.kdn.llm.local.models' 'path:.#nixosConfigurations.brys'
nix eval --impure --json \
  --apply 'x: x.config.specialisation.llms.configuration.kdn.llm.local.models' \
  'path:.#nixosConfigurations.brys'
```

## Notes

- The router vocabulary is `main | grunt | surveyed`; `main` is the primary router and is
  not in `kdn.llm.local.routers`. The `small` set was dead and is dropped.
- `qwen3.5-9b` stays declared with `enable = false`; clients skip disabled models, so the
  Pi JSON and catalog are unchanged.
- `servers.brys.package` is a key, not a `pkgs` value, so the data file stays pure.
