---
type: Research
description: Indexes every open deferred-decision mark of high or medium stakes that the aspect port left in the tree.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T06:40:00+02:00
---

# Deferred decisions — the index

The aspect port ran while the owner was away, so it recorded each design choice instead of
making it. This file lists every open mark of **high** or **medium** stakes in one table. The
owner reads one file and rules on each row.

Grades: **high** — a wrong choice costs data, breaks an adopter, or needs a rewrite later.
**medium** — a wrong choice costs rework in one file.

A row that the owner already ruled on is not here. A `DECIDED <date>` mark and a low-stakes
naming mark are also out.

| `file:line` | The open question | Stakes | Owning task |
|---|---|---|---|
| `modules/den/aspects/homebrew.nix:113` | Does the cask cleanup keep `"zap"`, or take nix-darwin's safe `"none"`? | high | [013](013-opt-in-boundaries/definition.md) |
| `modules/den/aspects/ssh-access.nix:66` | Does the shared schema file keep the personal default that the slot route reads? | high | [umbrella gap 6](definition.md) |
| `modules/den/aspects/llm.nix:35` | Does this aspect keep its own copy of the proxy unit, or include `llm-proxy` and write one instance? | high | [004](004-den-spike/definition.md) |
| `modules/den/aspects/llm-client.nix:27` | Does the aspect include `opencode` and own the API key variable, or keep the slot's plain settings write? | high | [004](004-den-spike/definition.md) |
| `modules/den/flake-module.nix:164` | Does the tree export one `denModules.<aspect>` name, or a `denModules.<aspect>-<class>` name per class? | high | [004](004-den-spike/definition.md) |
| `modules/universal/disks/config.nix:236` | Does a home directory take mode `700` or mode `0750`? | high | — |
| `modules/universal/fs/zfs/default.nix:104` | Does the baseline profile keep ZFS on a host with no ZFS filesystem? | high | [013](013-opt-in-boundaries/definition.md) |
| `013-opt-in-boundaries/definition.md:282` | Does a profile stay one bundle, or become a list of aspects? | high | [013](013-opt-in-boundaries/definition.md) |
| `013-opt-in-boundaries/definition.md:348` | Does the baseline profile declare any user at all? | high | [013](013-opt-in-boundaries/definition.md) |
| `modules/den/aspects/ssh-access.nix:81` | Does the option type keep the relative path read, or wait for the package to ship its schema as a flake output? | medium | [011](011-whole-tree-store-copies/definition.md) |
| `modules/den/aspects/ssh-access.nix:199` | Does the shim keep the generic name `ssh-access`, which can clash on the shell PATH? | medium | [004](004-den-spike/definition.md) |
| `modules/den/aspects/homebrew.nix:30` | Does a second aspect `homebrew-nix-managed` hold the immutable taps and the read-only variable? | medium | [004](004-den-spike/definition.md) |
| `modules/den/aspects/llm.nix:62` | Does the LAN gate stay in this aspect, or move to its own aspect that includes this one? | medium | [004](004-den-spike/definition.md) |
| `modules/den/aspects/llm.nix:796` | Does `compatProxy` stay a sub-toggle inside the aspect, against the one-aspect-per-toggle rule? | medium | [004](004-den-spike/definition.md) |
| `modules/den/aspects/signing.nix:130` | Does the aspect keep the `xdg.configHome` assumption for the git and jj config paths? | medium | [004](004-den-spike/definition.md) |
| `modules/den/aspects/signing.nix:226` | Does a user with no git get a silent no-op, or an assertion? | medium | [004](004-den-spike/definition.md) |
| `modules/den/aspects/signing.nix:57` | Does the script stay in the slot directory, or move under `modules/den/aspects/signing/`? | medium | [009](009-personal-data-folder/definition.md) |
| `modules/den/aspects/jj.nix:58` | Does the script stay in the slot directory, or move under the aspect's own directory? | medium | [009](009-personal-data-folder/definition.md) |
| `modules/den/aspects/nix.nix:46` | Does the script stay in the slot directory, or move under the aspect's own directory? | medium | [009](009-personal-data-folder/definition.md) |
| `modules/den/aspects/zellij.nix:50` | Does the script stay in the slot directory, or move under the aspect's own directory? | medium | [009](009-personal-data-folder/definition.md) |
| `checks/den-mvp/tests.nix:17` | Does the den check set stay without a VM test? | medium | [004](004-den-spike/definition.md) |
| `013-opt-in-boundaries/definition.md:304` | Does `stylix` keep a whole-tree switch, or become one theme aspect? | medium | [013](013-opt-in-boundaries/definition.md) |
| `013-opt-in-boundaries/definition.md:309` | Does the tap set stay a flake input pattern, or become the plain option `kdn.homebrew.taps`? | medium | [013](013-opt-in-boundaries/definition.md) |
| `013-opt-in-boundaries/definition.md:338` | Does `kdn.jj` keep the MCP coupling, or split a `jj-mcp` aspect? | medium | [013](013-opt-in-boundaries/definition.md) |
| `013-opt-in-boundaries/definition.md:343` | Does the nix policy stay one value, or split into three options? | medium | [013](013-opt-in-boundaries/definition.md) |
| `013-opt-in-boundaries/definition.md:353` | Does the `kdn-` unit-name and environment-variable prefix stay fixed? | medium | [013](013-opt-in-boundaries/definition.md) |
| `010-flake-input-overhead/research.md:481` | Does the subflake split happen, and on which trigger? | medium | [010](010-flake-input-overhead/definition.md) |
