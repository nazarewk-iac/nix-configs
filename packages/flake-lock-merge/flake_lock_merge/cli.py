"""
Merge two flake.lock files by updating the current lock with newer versions
of inputs that appear in both locks (based on lastModified). Inputs only in
one lock are left untouched (secondary-only inputs are ignored).

Usage:
  flake-lock-merge [-m file] <current> <secondary> [--output <out>]
  flake-lock-merge -m git <current> <secondary> [--path flake.lock] [--output <out>]
  flake-lock-merge -m jj <current> <secondary> [--path flake.lock] [--output <out>]

With no --output, writes to stdout.

--flake-nix is always read from the current filesystem (not VCS history) so it
should reflect the inputs you actually want in the merged result.
"""

import argparse
import json
import subprocess
import sys
from copy import deepcopy


def load_from_file(ref: str, path: str) -> dict:
    with open(ref) as f:
        return json.load(f)


def load_from_git(ref: str, path: str) -> dict:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def load_from_jj(ref: str, path: str) -> dict:
    result = subprocess.run(
        ["jj", "file", "show", "--revision", ref, path],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


LOADERS = {
    "file": load_from_file,
    "git":  load_from_git,
    "jj":   load_from_jj,
}


def last_modified(node: dict) -> int:
    return node.get("locked", {}).get("lastModified", 0)


def collect_transitive(node_key: str, nodes: dict, visited: set[str] | None = None) -> set[str]:
    """Return node_key plus all transitive node keys it references."""
    if visited is None:
        visited = set()
    if node_key in visited:
        return visited
    visited.add(node_key)
    node = nodes.get(node_key, {})
    for ref in node.get("inputs", {}).values():
        # inputs values are either a string (node key) or a list (follows path)
        if isinstance(ref, str):
            collect_transitive(ref, nodes, visited)
    return visited


def get_declared_inputs(flake_nix_path: str) -> list[str] | None:
    """Use nix eval to extract declared input names from flake.nix."""
    result = subprocess.run(
        [
            "nix", "eval", "--impure", "--json",
            "--expr", f"builtins.attrNames (import {flake_nix_path}).inputs",
        ],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"  warning: nix eval failed, skipping flake.nix reconciliation:\n    {result.stderr.strip()}", file=sys.stderr)
        return None
    return json.loads(result.stdout)


def merge_locks(lock_current: dict, lock_secondary: dict, declared_inputs: list[str] | None = None) -> dict:
    nodes_current = lock_current["nodes"]
    nodes_secondary = lock_secondary["nodes"]
    root_key = lock_current.get("root", "root")

    merged_nodes: dict = {}

    common_keys = (set(nodes_current) & set(nodes_secondary)) - {root_key}
    current_only = set(nodes_current) - set(nodes_secondary) - {root_key}
    secondary_only = set(nodes_secondary) - set(nodes_current) - {root_key}

    for key in current_only:
        merged_nodes[key] = deepcopy(nodes_current[key])

    for key in secondary_only:
        print(f"  {key}: only in secondary, skipping", file=sys.stderr)

    for key in common_keys:
        lm_current = last_modified(nodes_current[key])
        lm_secondary = last_modified(nodes_secondary[key])
        if lm_current >= lm_secondary:
            merged_nodes[key] = deepcopy(nodes_current[key])
            winner = "current"
        else:
            merged_nodes[key] = deepcopy(nodes_secondary[key])
            winner = "secondary"
        if lm_current != lm_secondary:
            print(
                f"  {key}: picked {winner} "
                f"(current={lm_current}, secondary={lm_secondary})",
                file=sys.stderr,
            )

    root_current = nodes_current.get(root_key, {})
    merged_root = deepcopy(root_current)

    # Reconcile root inputs against declared flake.nix inputs.
    if declared_inputs is not None:
        root_inputs = dict(merged_root.get("inputs", {}))
        root_secondary = nodes_secondary.get(root_key, {})
        secondary_inputs = root_secondary.get("inputs", {})

        for name in declared_inputs:
            if name in root_inputs:
                continue
            # Input is declared but missing from merged root — pull from secondary.
            if name in secondary_inputs:
                node_ref = secondary_inputs[name]
                print(f"  {name}: declared but missing from current, pulling from secondary", file=sys.stderr)
                root_inputs[name] = node_ref
                # Include the transitive closure of this node from secondary.
                if isinstance(node_ref, str):
                    for transitive_key in collect_transitive(node_ref, nodes_secondary):
                        if transitive_key not in merged_nodes:
                            if transitive_key in nodes_secondary:
                                merged_nodes[transitive_key] = deepcopy(nodes_secondary[transitive_key])
                                print(f"    + pulling transitive node {transitive_key!r} from secondary", file=sys.stderr)
            else:
                print(f"  {name}: declared but not found in either lock (needs nix flake update)", file=sys.stderr)

        # Warn about root inputs not in declared list (stale entries).
        for name in list(root_inputs):
            if name not in declared_inputs:
                print(f"  {name}: in merged root but not declared in flake.nix (stale?)", file=sys.stderr)

        merged_root["inputs"] = root_inputs

    merged_nodes[root_key] = merged_root

    return {"nodes": merged_nodes, "root": root_key, "version": lock_current.get("version", 7)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-m", "--mode", choices=LOADERS, default="file",
                        help="How to resolve refs: file (default), git, or jj")
    parser.add_argument("current", metavar="current")
    parser.add_argument("secondary", metavar="secondary")
    parser.add_argument("--path", default="flake.lock", help="Path within VCS tree (default: flake.lock)")
    parser.add_argument("--output", "-o", default="-", help="Output file (default: stdout)")
    parser.add_argument("--flake-nix", default="./flake.nix",
                        help="Path to flake.nix for input reconciliation (default: ./flake.nix); "
                             "always read from the current filesystem, not VCS history; "
                             "pass empty string to disable")
    args = parser.parse_args()

    load = LOADERS[args.mode]

    print(f"Loading current ({args.mode}): {args.current}", file=sys.stderr)
    lock_current = load(args.current, args.path)
    print(f"Loading secondary ({args.mode}): {args.secondary}", file=sys.stderr)
    lock_secondary = load(args.secondary, args.path)

    declared_inputs = None
    if args.flake_nix:
        print(f"Reading declared inputs from: {args.flake_nix}", file=sys.stderr)
        declared_inputs = get_declared_inputs(args.flake_nix)

    print("Merging (taking newer lastModified for common nodes)...", file=sys.stderr)
    merged = merge_locks(lock_current, lock_secondary, declared_inputs)

    out = json.dumps(merged, indent=2, sort_keys=True) + "\n"

    if args.output == "-":
        sys.stdout.write(out)
    else:
        with open(args.output, "w") as f:
            f.write(out)
        print(f"Written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
