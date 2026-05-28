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

Matching strategy: nodes are matched by their canonical input path starting from
root (e.g. root->devenv->flake-compat) rather than by node key names, which may
differ between locks due to deduplication suffixes (_2, _3, ...).
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


def build_path_map(nodes: dict, root_key: str) -> dict[tuple, str]:
    """
    DFS from root, mapping canonical input path -> node key.

    List-valued inputs are 'follows' aliases and are not traversed as new nodes.
    A node key may be shared (appears at multiple paths); each path is recorded.
    """
    path_to_key: dict[tuple, str] = {}
    # visited tracks which node keys we've already fully traversed, to avoid
    # infinite loops on shared nodes (we still record the path, just don't re-DFS)
    visited: set[str] = set()

    def dfs(key: str, path: tuple) -> None:
        path_to_key[path] = key
        if key in visited:
            return
        visited.add(key)
        node = nodes.get(key, {})
        for input_name, ref in node.get("inputs", {}).items():
            if isinstance(ref, str):  # list = follows alias, skip
                dfs(ref, path + (input_name,))

    dfs(root_key, ())
    return path_to_key


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


def fresh_key(preferred: str, taken: set[str]) -> str:
    """Return preferred if not taken, otherwise preferred_2, preferred_3, ..."""
    if preferred not in taken:
        return preferred
    i = 2
    while f"{preferred}_{i}" in taken:
        i += 1
    return f"{preferred}_{i}"


def merge_locks(lock_current: dict, lock_secondary: dict, declared_inputs: list[str] | None = None) -> dict:
    nodes_c = lock_current["nodes"]
    nodes_s = lock_secondary["nodes"]
    root_key = lock_current.get("root", "root")
    version = lock_current.get("version", 7)

    # Build path->key maps for both locks.
    paths_c = build_path_map(nodes_c, root_key)
    paths_s = build_path_map(nodes_s, root_key)

    all_paths = set(paths_c) | set(paths_s)
    # Invert: key -> set of paths (for current lock, used to find a preferred name)
    key_to_paths_c: dict[str, list[tuple]] = {}
    for path, key in paths_c.items():
        key_to_paths_c.setdefault(key, []).append(path)

    # For each path, decide which node wins.
    # path -> node dict (from whichever lock won)
    path_to_node: dict[tuple, dict] = {}
    # path -> source ("current" | "secondary")
    path_to_source: dict[tuple, str] = {}

    for path in all_paths:
        in_c = path in paths_c
        in_s = path in paths_s
        if path == ():
            # Root is always taken from current structure; handled separately.
            continue
        if in_c and not in_s:
            path_to_node[path] = deepcopy(nodes_c[paths_c[path]])
            path_to_source[path] = "current"
        elif in_s and not in_c:
            path_to_node[path] = deepcopy(nodes_s[paths_s[path]])
            path_to_source[path] = "secondary"
            print(f"  {'>'.join(path)}: only in secondary, keeping", file=sys.stderr)
        else:
            lm_c = last_modified(nodes_c[paths_c[path]])
            lm_s = last_modified(nodes_s[paths_s[path]])
            if lm_c >= lm_s:
                path_to_node[path] = deepcopy(nodes_c[paths_c[path]])
                path_to_source[path] = "current"
                if lm_c != lm_s:
                    print(f"  {'>'.join(path)}: kept current (current={lm_c}, secondary={lm_s})", file=sys.stderr)
            else:
                path_to_node[path] = deepcopy(nodes_s[paths_s[path]])
                path_to_source[path] = "secondary"
                print(f"  {'>'.join(path)}: picked secondary (current={lm_c}, secondary={lm_s})", file=sys.stderr)

    # Assign merged node keys.
    # Prefer the current lock's key name for any path that exists in current.
    # For secondary-only paths use the secondary key name, deduplicating as needed.
    taken: set[str] = set()
    # canonical path -> merged key name
    path_to_merged_key: dict[tuple, str] = {(): root_key}
    taken.add(root_key)

    # First pass: paths present in current keep their current key name.
    for path in sorted(paths_c):
        if path == ():
            continue
        key = paths_c[path]
        if key not in taken:
            path_to_merged_key[path] = key
            taken.add(key)

    # Shared current nodes: different paths may map to the same key.
    # Any remaining current paths that share a key with an already-assigned path
    # point to the same merged key.
    for path in sorted(paths_c):
        if path == () or path in path_to_merged_key:
            continue
        key = paths_c[path]
        # Find the merged key that was assigned to another path sharing this node key.
        assigned = next((path_to_merged_key[p] for p in path_to_merged_key if p != () and paths_c.get(p) == key), None)
        if assigned:
            path_to_merged_key[path] = assigned

    # Second pass: secondary-only paths get new (possibly renamed) keys.
    for path in sorted(all_paths - set(paths_c)):
        if path == ():
            continue
        preferred = paths_s[path]
        # Strip existing _N suffix to get the base name, then pick a fresh key.
        base = preferred.rstrip("0123456789").rstrip("_") if "_" in preferred else preferred
        # Try the secondary key first, then base, then numbered.
        key = fresh_key(preferred, taken)
        if key != preferred:
            key = fresh_key(base, taken)
        path_to_merged_key[path] = key
        taken.add(key)

    # Reverse: merged_key -> canonical path (for building the nodes dict)
    merged_key_to_path: dict[str, tuple] = {}
    for path, key in path_to_merged_key.items():
        # A key may appear at multiple paths (shared node); record the shortest path.
        if key not in merged_key_to_path or len(path) < len(merged_key_to_path[key]):
            merged_key_to_path[key] = path

    # Build merged nodes, rewriting inputs refs to use merged key names.
    def rewrite_inputs(node: dict, path: tuple) -> dict:
        """Rewrite a node's inputs map so all string refs use merged key names."""
        node = deepcopy(node)
        new_inputs = {}
        for input_name, ref in node.get("inputs", {}).items():
            if isinstance(ref, list):
                new_inputs[input_name] = ref  # follows path, keep as-is
            else:
                child_path = path + (input_name,)
                if child_path in path_to_merged_key:
                    new_inputs[input_name] = path_to_merged_key[child_path]
                else:
                    # Ref not in our path map — keep original (shouldn't happen).
                    new_inputs[input_name] = ref
        node["inputs"] = new_inputs
        return node

    merged_nodes: dict = {}
    for merged_key, path in merged_key_to_path.items():
        if path == ():
            continue  # root handled below
        node = path_to_node.get(path, {})
        node = rewrite_inputs(node, path)
        if node.get("inputs") == {}:
            del node["inputs"]
        merged_nodes[merged_key] = node

    # Build root node: start from current root, rewrite inputs refs.
    root_node = deepcopy(nodes_c.get(root_key, {}))
    root_inputs = dict(root_node.get("inputs", {}))

    # Ensure all declared inputs are present in root.
    if declared_inputs is not None:
        secondary_root_inputs = nodes_s.get(root_key, {}).get("inputs", {})
        for name in declared_inputs:
            if name in root_inputs:
                continue
            child_path = (name,)
            if child_path in path_to_merged_key:
                root_inputs[name] = path_to_merged_key[child_path]
                print(f"  {name}: added to root from secondary", file=sys.stderr)
            else:
                print(f"  {name}: declared but not found in either lock (needs nix flake update)", file=sys.stderr)

        for name in list(root_inputs):
            if name not in declared_inputs:
                print(f"  {name}: in merged root but not declared in flake.nix (stale?)", file=sys.stderr)

    # Rewrite root inputs using merged key names.
    new_root_inputs = {}
    for name, ref in root_inputs.items():
        if isinstance(ref, list):
            new_root_inputs[name] = ref
        else:
            child_path = (name,)
            new_root_inputs[name] = path_to_merged_key.get(child_path, ref)
    root_node["inputs"] = new_root_inputs
    merged_nodes[root_key] = root_node

    return {"nodes": merged_nodes, "root": root_key, "version": version}


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

    print("Merging (matching by input path, taking newer lastModified)...", file=sys.stderr)
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
