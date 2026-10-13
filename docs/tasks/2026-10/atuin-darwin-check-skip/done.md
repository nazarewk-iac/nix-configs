---
type: Solution
description: Add a darwin-only overlay that sets `doCheck = false` for `atuin`, with a comment that names nixpkgs issue #573527.
task: definition.md
authored_by: agent
timestamp: 2026-10-14T00:03:02+02:00
---

# Solution

## Root cause analysis

`atuin` 18.23.0 runs two e2e test binaries that drive an interactive bash in a pty. Both fail on
`aarch64-darwin`:

- `e2e_capture::filtered_commands_leave_no_captured_output` prints "timed out waiting for the last
  command's captured output; captured: []".
- `e2e_pty` fails 13 of 80 tests.

The package sets `__darwinAllowLocalNetworking = true`, and `sandbox = false` on this host, so
neither is the cause. The failure is nixpkgs issue #573527. It is not a local defect and it is not
a flake.

## Solution

`flake.nix`, in the `overlays.packages` chain, after the `typescript-language-server` entry:

```nix
(final: prev:
  prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
    atuin = prev.atuin.overrideAttrs (_: {
      doCheck = false;
    });
  })
```

The overlay is a no-op on Linux. The comment above it names issue #573527 and states the removal
condition.

## Verification steps

- `nix build '.#darwinConfigurations.anji.pkgs.atuin'` on `anji` succeeds.
- `darwin-rebuild switch --flake .#anji` on `anji` completes; `/run/current-system` moves to the new
  generation and the nix daemon is up.
- Linux hosts are unchanged: their `atuin` builds already passed.

## Follow-up notes

Remove the overlay when `atuin` passes its darwin tests again, or when a `.flake.patches` entry for
issue #573527 exists. The upstream request is to ignore the failing test on darwin.
