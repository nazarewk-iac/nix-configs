# Packaging Python Scripts

Python scripts in `packages/` use `lib.kdn.mkPythonScript` (defined in `lib/python/mkPythonScript.nix`).

## Always scaffold with `init-py-script`

```bash
nix run .#init-py-script -- <package-name>
```

This creates `packages/<package-name>/` with the correct structure and registers it in `packages/default.nix`. After scaffolding, fix these things the template leaves wrong:

1. `name = "nix-name-placeholder"` in `default.nix` — replace with the actual package name
2. `requirementsFileText` — remove placeholder deps (`fire`, `structlog`) if not needed
3. Replace `package_name/cli.py` with the actual implementation

The `pythonModule` and `src` fields are set correctly by the scaffold; leave them as-is.

## Typical `default.nix` (after scaffold + fixup)

```nix
{
  pkgs,
  lib,
  __inputs__ ? { },
  ...
}:
let
  python = pkgs.python314;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./package_name;
  };

  mkPythonScript =
    if __inputs__ ? inputs.kdn-configs-src then
      import (__inputs__.inputs.kdn-configs-src + /lib/python/mkPythonScript.nix) { inherit lib pkgs; }
    else
      lib.kdn.mkPythonScript pkgs;
in
mkPythonScript {
  inherit src python;
  name = "tool-name";                    # MUST match binary name; scaffold leaves "nix-name-placeholder" — fix this
  pythonModule = "package_name.cli";
  requirementsFileText = ''
    some-dep
  '';
  runtimeDeps = with pkgs; [             # optional: non-Python binaries on PATH
    #git
  ];
}
```

## Key parameters of `mkPythonScript`

| Parameter | Default | Notes |
|---|---|---|
| `src` | required | Use `lib.fileset.toSource` to include only `.py` files |
| `name` | required | Binary name; also the package name |
| `python` | required | e.g. `pkgs.python314` |
| `pythonModule` | `""` | If set, runs `python -m <module>`; otherwise runs `scriptFile` directly |
| `scriptFile` | auto | Defaults to `src/<name>.py` if it exists, else `scriptFileText` |
| `scriptFileText` | `""` | Inline script text (alternative to a file) |
| `requirementsFileText` | `""` | pip-style requirements (one package per line, no version pins needed) |
| `requirementsFile` | auto | Path to `requirements.txt`; auto-detected from `src` |
| `runtimeDeps` | `[]` | Non-Python binaries to add to PATH via `makeBinaryWrapper` |
| `makeWrapperArgs` | `[]` | Extra `makeWrapper` arguments |

## Notes

- **stdlib-only scripts**: set `requirementsFileText = ''` (empty) — the package builds fine with no pip dependencies
- **`argparse` prog name**: `sys.argv[0]` shows `python3.14 -m package.cli` in `--help`. Pass `prog="tool-name"` to `ArgumentParser` to fix this
- **Manual registration**: if not using `init-py-script`, add to `packages/default.nix` before the `# AUTO_PACKAGE_PLACEHOLDER #` line, alphabetically sorted:
  ```nix
  tool-name = pkgs.callPackage ./tool-name { };
  ```
