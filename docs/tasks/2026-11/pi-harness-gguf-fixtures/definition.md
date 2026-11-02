---
type: Task
description: Self-host the tiny GGUF fixtures the Pi harness checks need, so an upstream repo rename or deletion cannot break the build.
status: open
authored_by: agent
timestamp: 2026-11-01T08:30:00+01:00
---

# Self-host the Pi harness GGUF fixtures

## Why

`checks/pi-harness/fixtures.nix` fetches two tiny GGUF models to run Pi against a
throwaway `llama-server`. Today the URLs are pinned to an **immutable Hugging Face
commit** on top of a `sha256`, which was the best available:

```
https://huggingface.co/ggml-org/models-moved/resolve/<commit>/tinyllamas/stories260K.gguf
https://huggingface.co/ggml-org/models-moved/resolve/<commit>/tinyllamas/stories15M.gguf
```

Two problems remain, and both have already bitten once:

1. **The repo was renamed.** `ggml-org/models` became `ggml-org/models-moved`, and the
   old `main` URL only 307-redirects. A redirect is not a promise: this is a real
   occurrence, not a hypothetical.
2. **A deletion breaks even a commit URL.** If the upstream repo is removed, the pinned
   URL stops resolving and every check that needs a fixture fails to build.

The hash pins the _bytes_; it does not pin _availability_. A mirror closes that gap.

## What

1. Copy both files into storage we control (S3, Nextcloud, or a `fetchurl` from a URL the
   owner commits to keeping):
   - `stories260K.gguf` — 1 MB, size 1185376, `x-linked-etag` `270cba1b…d256d`
   - `stories15M.gguf` — 98 MB, size 98357920, `x-linked-etag` `61b50d45…53704a`
2. Repoint `checks/pi-harness/fixtures.nix` at the mirror, keeping the same `sha256`
   hashes (`sha256-Jwy6G9…JW0=`, `sha256-YbUNRX…cEo=`). A copied file that differs
   fails the build, which is the safety net.
3. State in the file comment which upstream commit the copy corresponds to, so a future
   bump can re-derive it.

## Acceptance

- `checks/pi-harness/fixtures.nix` names only a mirror host we control, no
  `huggingface.co`.
- `nix build .#checks.x86_64-linux.pi-harness-plumbing` still succeeds on a cold store.
- An offline build after the first fetch works (the FOD is cached).

## Open question

Is `stories15M` (98 MB) worth keeping? The current checks run entirely on `stories260K`;
`stories15M` is a fixture with no current consumer. Drop it from this task if no check
starts using it — one 1 MB mirror file is a far smaller commitment.
