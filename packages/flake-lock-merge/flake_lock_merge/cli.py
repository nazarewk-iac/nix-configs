"""
Merge two flake.lock files by taking the newer version of each common input
(based on lastModified), and including all unique inputs from either side.

Usage:
  flake-lock-merge [-m file] <current> <secondary> [--output <out>]
  flake-lock-merge -m git <current> <secondary> [--path flake.lock] [--output <out>]
  flake-lock-merge -m jj <current> <secondary> [--path flake.lock] [--output <out>]

With no --output, writes to stdout.
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


def merge_locks(lock_current: dict, lock_secondary: dict) -> dict:
    nodes_current = lock_current["nodes"]
    nodes_secondary = lock_secondary["nodes"]
    root_key = lock_current.get("root", "root")

    merged_nodes: dict = {}

    all_keys = set(nodes_current) | set(nodes_secondary)
    non_root_keys = all_keys - {root_key}

    for key in non_root_keys:
        if key in nodes_current and key in nodes_secondary:
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
        elif key in nodes_current:
            merged_nodes[key] = deepcopy(nodes_current[key])
            print(f"  {key}: only in current", file=sys.stderr)
        else:
            merged_nodes[key] = deepcopy(nodes_secondary[key])
            print(f"  {key}: only in secondary", file=sys.stderr)

    root_current = nodes_current.get(root_key, {})
    root_secondary = nodes_secondary.get(root_key, {})
    merged_root_inputs = {**root_secondary.get("inputs", {}), **root_current.get("inputs", {})}
    merged_root = {**deepcopy(root_current), "inputs": merged_root_inputs}
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
    args = parser.parse_args()

    load = LOADERS[args.mode]

    print(f"Loading current ({args.mode}): {args.current}", file=sys.stderr)
    lock_current = load(args.current, args.path)
    print(f"Loading secondary ({args.mode}): {args.secondary}", file=sys.stderr)
    lock_secondary = load(args.secondary, args.path)

    print("Merging (taking newer lastModified for common nodes)...", file=sys.stderr)
    merged = merge_locks(lock_current, lock_secondary)

    out = json.dumps(merged, indent=2, sort_keys=True) + "\n"

    if args.output == "-":
        sys.stdout.write(out)
    else:
        with open(args.output, "w") as f:
            f.write(out)
        print(f"Written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
