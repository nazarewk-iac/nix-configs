---
type: Solution
description: Closed the runner-evaluation sub-task as researched-only. No runner is built or adopted. Strata does not fit brys; ik_llama.cpp is the lower-risk future candidate.
task: definition.md
authored_by: agent
timestamp: 2026-10-19T20:30:00+02:00
---

# 003 — Runner evaluation: solution

## Root cause analysis

The task asked to package Strata in Nix and to compare it, and other runners,
against llama.cpp on brys, judged on a like-for-like benchmark. The desk
research found that Strata cannot run on brys at all. A build or a benchmark of
Strata on this host is not possible, so the task cannot reach its original
acceptance criteria on this hardware.

## Decision

Close the sub-task as **researched-only**. No runner is built and no runner is
adopted at this time. This is the user's decision.

## Why

Strata is not viable on brys. The [feasibility study](strata-feasibility.research.md)
records the reasons:

- Strata has no Vulkan backend for its own engine. Its AMD path is HIP/ROCm
  only.
- The HIP target allow-list holds gfx1100, gfx1101, gfx1102, gfx1200, gfx1201,
  gfx1030, gfx1031, gfx1151. The W6600 is gfx1032, which is absent. gfx1032 is
  also not an official ROCm 7 target.
- Strata has no pure CPU-only mode. Its engine always needs a usable GPU.
- The total-memory rule (RAM plus VRAM) passes on brys, but the 8 GB VRAM is
  below the 12 GB recommendation.

ik_llama.cpp is the lower-risk future candidate. Its CPU path is a first-class,
maintained backend (AVX2, no GPU needed), and it compares cleanly against
llama.cpp on the same GGUF models and the same CPU. The user chose not to build
it at this time.

## What was delivered

- [runners.research.md](runners.research.md) — the candidate survey, with a
  ranked shortlist from best to worst fit for brys.
- [strata-feasibility.research.md](strata-feasibility.research.md) — the Strata
  feasibility study, with Verdict A (runs on brys as-is: no), Verdict B (the
  fallback options), and the ik_llama.cpp alternative.

## Verification steps

Desk research only. No build and no hardware run.

- `nix eval nixpkgs#strata` fails: Strata is not in nixpkgs.
- The upstream Strata flake is a CUDA `devShell` only. It has no `packages.`
  output. See [runners.research.md](runners.research.md), section 2.

## Follow-up notes

The condition to reopen this task is one of these two events:

1. A GPU or a runner that supports gfx1032 becomes available.
2. The user decides to package ik_llama.cpp.

The Nix requirement stays on record: any future runner must be a Nix package in
this repository (under `packages/`), with a pinned source and a deterministic
build. Do not build a runner from a hand-made checkout and run that.
