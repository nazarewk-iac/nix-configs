"""Core logic for kdn-disko-zfs, kept free of I/O so it can be unit-tested.

The wrapper turns a host's disko-declared ZFS datasets into a disko-zfs "spec"
(JSON), compares it against the live pool, and plans/applies the missing ones.
"""

from __future__ import annotations

import json
from typing import Any

SPEC_KEYS = ("datasets", "ignoredDatasets", "ignoredProperties", "logLevel")


def gen_spec_expr(repo: str, host: str) -> str:
    """Nix expression that evaluates host's disko zpool datasets to a spec JSON.

    It mirrors numtide/disko-zfs's own disko-to-spec derivation: every dataset
    under `disko.devices.zpool.<pool>.datasets` (except `__root`) becomes
    `<pool>/<dataset>` with that dataset's disko `options` as ZFS properties, and
    the pool root itself (`__root`) is added too.
    """
    return f"""
let
  f = builtins.getFlake "{repo}";
  lib = f.inputs.nixpkgs.lib;
  cfg = f.nixosConfigurations."{host}".config;
  pools = cfg.disko.devices.zpool;
  mk = n: v:
    (lib.mapAttrsToList
      (d: s: {{ name = "${{n}}/${{d}}"; value = {{ properties = s.options or {{ }}; }}; }})
      (lib.filterAttrs (d: _: d != "__root") v.datasets))
    ++ [ {{ name = n; value = {{ properties = v.datasets.__root.options or {{ }}; }}; }} ];
  datasets = lib.listToAttrs (lib.flatten (lib.mapAttrsToList mk pools));
in
{{ datasets = datasets; ignoredDatasets = [ ]; ignoredProperties = [ ]; logLevel = "info"; }}
""".strip()


def parse_spec(text: str) -> dict[str, Any]:
    spec = json.loads(text)
    if not isinstance(spec, dict) or "datasets" not in spec:
        raise ValueError("spec JSON has no 'datasets' key")
    return spec


def dataset_names(spec: dict[str, Any]) -> list[str]:
    return sorted((spec.get("datasets") or {}).keys())


def compute_ignored(spec_datasets: list[str], live_datasets: list[str]) -> list[str]:
    """Live datasets the spec does not declare, minus ancestors of declared ones.

    Everything else (e.g. podman container storage, libvirt volumes) becomes an
    ignore, so disko-zfs never proposes destroying it. A live dataset that is an
    ancestor of a declared dataset is left alone (not ignored, not destroyed).
    """
    want = set(spec_datasets)
    out: list[str] = []
    for live in live_datasets:
        if live in want:
            continue
        if any(w.startswith(live + "/") for w in want):
            continue
        out.append(live)
    return sorted(out)


def merge_ignores(spec: dict[str, Any], ignored: list[str]) -> dict[str, Any]:
    merged = dict(spec)
    existing = list(merged.get("ignoredDatasets") or [])
    merged["ignoredDatasets"] = sorted(set(existing) | set(ignored))
    return merged


def dry_run_commands(spec: dict[str, Any]) -> list[str]:
    """The `zfs create` commands the spec implies, without contacting a host."""
    cmds: list[str] = []
    for name, data in sorted((spec.get("datasets") or {}).items()):
        props = (data or {}).get("properties") or {}
        opts = " ".join(f"-o{k}={v}" for k, v in props.items())
        cmds.append("zfs create " + (opts + " " if opts else "") + name)
    return cmds


def has_destructive(plan_text: str) -> bool:
    for line in plan_text.splitlines():
        stripped = line.strip().lstrip(">").strip()
        if stripped.startswith("zfs destroy"):
            return True
    return False
