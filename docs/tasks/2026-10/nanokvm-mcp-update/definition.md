---
type: Task
description: Update the Sipeed NanoKVM at `kvm-2795` to 2.5.2 and enable its MCP service, so an agent can drive the `anji` Mac mini over KVM when a broken Nix install makes SSH unusable.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-08T21:05:00+02:00
---

# Bring the `anji` recovery NanoKVM up to an MCP-capable version

## Context

- `anji` is the Apple Silicon Mac mini that a Nix recovery would need to rebuild. If its Lix or
  nix-darwin install breaks, SSH stops working and the only way back in is the keyboard and mouse
  through a KVM.
- The KVM is a Sipeed NanoKVM Cube at `ssh kvm-2795.lan.etra.net.int.kdn.im` (root, passwordless).
  It is a riscv64 Buildroot box running `NanoKVM-Server`, version 2.4.3 (`/kvmapp/version`).
- The NanoKVM web UI has an over-the-air update. The goal was 2.5.2, which carries the MCP service
  an agent can drive without a browser.
- The OTA update to 2.5.2 failed and left no visible reason.

## Problem

The OTA update reported no useful error. Two unknowns: why the update failed, and how to reach an
MCP interface that can capture the `anji` screen and inject keyboard and mouse.

## Approach

1. Read the NanoKVM open-source update path to find where it downloads, how it stages, and what it
   logs.
2. Reproduce the failure conditions from the device: DNS, TLS, the CDN response, and the manifest.
3. Fix the root cause without reflashing.
4. Enable the MCP service and prove it can capture a screen.

See [done.md](done.md) for the root cause and the fix.
