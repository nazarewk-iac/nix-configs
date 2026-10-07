---
type: Status
description: The two llama.cpp builds, the benchmark and the brys deployment are done; the upstreaming-versus-override decision stays open.
task: definition.md
authored_by: agent
timestamp: 2026-10-07T10:00:00+02:00
---

# Status: llama.cpp latest package

## Done so far

- `packages/llama-cpp/default.nix` holds both derivations:
  `llama-cpp-v0_6_0` and `llama-cpp-unsloth-mtp`.
- Both derivations build and expose the `draft-mtp` spec type.
- The benchmark ran on brys. The results table is in
  [definition.md](definition.md#results-brys-2026-10-07).
- The deployed config on brys is C: the Unsloth fork with MTP. See
  `hosts/brys/llm-qwen.nix`.
- The `perf.mmap` slot option is now nullable. The two new builds dropped
  `--mmap`, and the router rejects the key. `hosts/brys/llm.nix` sets
  `mmap = null` for Qwen.
- The update steps are in
  [packages/llama-cpp/README.md](../../../../packages/llama-cpp/README.md).

## Remaining

- Decide the upstreaming question: wait for nixpkgs, or keep the local
  override. See "Open question: upstreaming vs override" in
  [definition.md](definition.md#open-question-upstreaming-vs-override).

## Next directions

- Check whether a later nixpkgs `llama-cpp` carries the `qwen4exp` MTP graph.
- If yes, delete the matching custom derivation and use `pkgs.llama-cpp`.
- If no, keep `packages/llama-cpp` and record the decision here.
