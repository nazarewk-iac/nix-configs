---
type: Solution
description: The denLib.imports augmentation line works on a universal host; recorded the nested-list trap, the source-tree drvPath delta, and the absent den.default.
timestamp: 2026-09-25T18:40:00+02:00
authored_by: agent
---

# Solution

## Root cause analysis

Sub-task 000 asked whether a universal (old-tree) host can adopt one den aspect through the den
library route, so a host migrates one aspect at a time. The route is `denLib.imports`.

The mechanism works. The verification found four caveats, and one of them is a measurement trap.

## Solution

No code change. The task is a verification unit. The exact line, added inside the host's own
`imports` list:

```nix
imports = [
  kdnConfig.self.nixosModules.default
  slots.config.nixos
  {
    imports = kdnConfig.self.denLib.imports {
      class = "nixos";
      aspects = [ "ca-dag" "certificates" ];
    };
  }
];
```

The wrapper `{ imports = …; }` is mandatory: `denLib.imports` returns a **list**, and a bare list
inside an `imports` list fails with `error: Module imports can't be nested lists`.

## Verification steps

Measured on the real universal host `hosts/oams/default.nix`:

| Command | Result |
|---|---|
| `nix eval --no-eval-cache --raw '.#nixosConfigurations.oams.config.system.build.toplevel.drvPath'` | exit 0, no "already declared" error |
| `nix eval --no-eval-cache --json '.#nixosConfigurations.oams.config.kdn.certificates'` | `{"certs":{}}` |
| `nix eval --no-eval-cache --json '.#nixosConfigurations.oams.config.kdn.ca-dag'` | `{"cas":{}}` |
| the same line on `brys`, `etra`, `moss` | toplevel evaluates, exit 0 |
| `nix build --no-eval-cache -L '.#checks.x86_64-linux.standalone-aspects'` | pass |

## Follow-up notes

Four caveats, all measured. The full detail is in the task `.worklog.md`.

1. **The bare list fails.** See above. Keep the `{ imports = …; }` wrapper.
2. **The toplevel `drvPath` changes even when the aspect is a true no-op.** The cause is not the
   aspect. `environment.etc."kdn/source-flake"` symlinks the whole flake source tree, so any edit to
   any tracked file changes the `etc` derivation. Once every `/nix/store/<hash>-` segment is
   normalised to a placeholder, the `etc` build command is byte-identical with and without the line.
   So an augmentation line is a no-op at the value level, and a `drvPath` comparison against a
   previous tree is not a valid no-op test.
3. **`den.default` is absent on the library route.** `den.nixModule` exposes only
   `{ aspects, lib, policies }`. The explicit per-entity include of decision D3 is forced here.
4. **Evaluation cost.** `denLib.imports` runs a fresh den library evaluation per call
   (`modules/den/lib.nix:483`), about one second. A universal host pays it once per line.
