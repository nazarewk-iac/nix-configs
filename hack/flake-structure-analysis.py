#!/usr/bin/env python3
"""Analyze the flake input graph and report missing `follows` declarations.

`flake.lock` encodes two kinds of input edges:

- a **string** names a node directly: the referrer declares its own source for that input;
- a **list** is a `follows` declaration: the referrer reuses the node found on that path from
  the root.

So a transitive input with a string edge pins its own revision, and one upstream bump has to be
repeated for every such revision. This script counts, per repository:

- `direct`     edges the root flake declares itself;
- `followed`   transitive edges that already declare `follows`;
- `unfollowed` transitive edges that name their own source.

The rows are sorted by `unfollowed` first, so the most valuable `follows` declarations come on
top. Repositories with a single reference are skipped by default: they cannot be followed to
anything else, and they are listed last when `--single-references` is given.

Examples:

    hack/flake-structure-analysis.py
    hack/flake-structure-analysis.py --single-references
    hack/flake-structure-analysis.py --json
    hack/flake-structure-analysis.py --metadata /tmp/flake-metadata.json
    nix flake metadata --json | hack/flake-structure-analysis.py --metadata -

Exit code is 0 even when suggestions exist; use `--fail-on-suggestions` to change that.
"""

import argparse
import json
import sys
from collections import defaultdict, deque


def load_graph(args):
    if args.metadata:
        if args.metadata == "-":
            data = json.load(sys.stdin)
        else:
            with open(args.metadata) as f:
                data = json.load(f)
        # `nix flake metadata --json` nests the graph under `locks`.
        return data.get("locks", data)
    with open(args.lock) as f:
        return json.load(f)


def repo_key(node):
    """Return (repo, project) for a lock node.

    `repo` is the full `owner/name`, so a fork stays distinct from its upstream. `project` is
    only the repository name, which groups a fork with the project it forks.
    """
    locked = node.get("locked") or {}
    owner = locked.get("owner")
    repo = locked.get("repo")
    if owner and repo:
        return f"{owner}/{repo}", repo
    kind = locked.get("type", "unknown")
    url = locked.get("url", "")
    path = locked.get("path", "")
    ident = url or path or kind
    return f"{kind}:{ident}", ident


def walk(nodes):
    """Return {node: [input names from root]}, the edge list, and a follows resolver."""
    paths = {"root": []}
    queue = deque(["root"])
    edges = []

    def resolve(path, seen=()):
        """Resolve a follows path (a list of input names) to a node name, or None."""
        node = "root"
        for name in path:
            node_def = nodes.get(node) or {}
            value = (node_def.get("inputs") or {}).get(name)
            if value is None:
                return None
            if isinstance(value, list):
                if tuple(path) in seen:
                    return None
                return resolve(value, seen + (tuple(path),))
            node = value
        return node

    while queue:
        name = queue.popleft()
        node = nodes.get(name) or {}
        for input_name, value in (node.get("inputs") or {}).items():
            path = paths[name] + [input_name]
            if isinstance(value, list):
                target = resolve(value)
                kind = "follows"
                declared = value
            else:
                target = value
                kind = "node"
                declared = None
            if target is None:
                continue
            edges.append(
                {
                    "from": name,
                    "input": input_name,
                    "to": target,
                    "path": path,
                    "kind": kind,
                    "declared": declared,
                }
            )
            if target not in paths:
                paths[target] = path
                queue.append(target)
    return paths, edges


def project_names(nodes, fork_owners):
    """Group fork and upstream under one project name; keep unrelated repos separate.

    A bare repository name is only safe as a group key when a fork owner takes part: two
    unrelated repositories can both be named `default`. Everything else keeps `owner/name`.
    """
    owners = defaultdict(set)
    for node in nodes.values():
        locked = node.get("locked") or {}
        if locked.get("owner") and locked.get("repo"):
            owners[locked["repo"]].add(locked["owner"])
    forked = {name for name, who in owners.items() if who & fork_owners}

    def name_for(repo):
        owner, _, name = repo.partition("/")
        return name if name in forked else repo

    return name_for


def analyze(nodes, edges, include_single, fork_owners):
    name_for = project_names(nodes, fork_owners)
    by_project = defaultdict(list)
    for edge in edges:
        target_node = nodes.get(edge["to"]) or {}
        repo, _ = repo_key(target_node)
        by_project[name_for(repo)].append({**edge, "repo": repo})

    rows = []
    suggestions = []
    for project, refs in by_project.items():
        root_edges = [r for r in refs if len(r["path"]) == 1]
        transitive = [r for r in refs if len(r["path"]) > 1]
        followed = [r for r in transitive if r["kind"] == "follows"]
        unfollowed = [r for r in transitive if r["kind"] == "node"]
        nodes_used = {r["to"] for r in refs}
        total = len(refs)

        if total <= 1 and not include_single:
            continue

        followed_by_node = defaultdict(int)
        for ref in followed:
            followed_by_node[ref["to"]] += 1

        def canonical_for(input_name):
            """Pick the root input a given transitive input should follow.

            Score by exact name, then shared name tokens (`nixos-stable` prefers
            `nixpkgs-stable`), then the input most references already follow.
            """
            if not root_edges:
                return None

            def score(edge):
                want = input_name.replace("_", "-").split("-")
                have = edge["input"].replace("_", "-").split("-")
                exact = 2 if edge["input"] == input_name else 0
                overlap = len(set(want) & set(have))
                return (-exact, -overlap, -followed_by_node.get(edge["to"], 0))

            return min(root_edges, key=score)

        canonical_counts = defaultdict(int)
        for ref in unfollowed:
            target = canonical_for(ref["input"])
            if target is not None:
                canonical_counts[target["input"]] += 1
        canonical_name = (
            max(canonical_counts, key=canonical_counts.get)
            if canonical_counts
            else None
        )

        row = {
            "project": project,
            "repos": sorted({r["repo"] for r in refs}),
            "direct": len(root_edges),
            "followed": len(followed),
            "unfollowed": len(unfollowed),
            "total": total,
            "revisions": len(nodes_used),
            "percent_unfollowed": round(
                100.0 * len(unfollowed) / (len(followed) + len(unfollowed)), 1
            )
            if (len(followed) + len(unfollowed))
            else 0.0,
            "canonical": canonical_name,
            "single_reference": total <= 1,
        }
        rows.append(row)

        seen = set()
        for ref in sorted(unfollowed, key=lambda r: r["path"]):
            target = canonical_for(ref["input"])
            if target is None:
                key = ("none", project)
                if key not in seen:
                    seen.add(key)
                    suggestions.append(
                        {
                            "repo": project,
                            "declaration": None,
                            "comment": f"no top-level input for {project}; add one before following",
                        }
                    )
                continue
            chain = "inputs." + ".inputs.".join(ref["path"])
            declaration = f'{chain}.follows = "{target["input"]}";'
            if declaration in seen:
                continue
            seen.add(declaration)
            suggestions.append(
                {
                    "repo": project,
                    "declaration": declaration,
                    "comment": f"{ref['input']} in {'/'.join(ref['path'][:-1]) or 'root'} pins its own revision",
                }
            )

    rows.sort(
        key=lambda r: (
            1 if r["single_reference"] else 0,
            -r["unfollowed"],
            -r["total"],
            r["project"],
        )
    )
    suggestions.sort(key=lambda s: (s["declaration"] is None, s["declaration"] or ""))
    return rows, suggestions


def print_human(rows, suggestions):
    if not rows:
        print("No repositories with more than one reference.")
        return
    headers = ["project", "direct", "followed", "unfollowed", "%unfol", "revs"]
    table = [
        [
            r["project"],
            str(r["direct"]),
            str(r["followed"]),
            str(r["unfollowed"]),
            f"{r['percent_unfollowed']:.0f}%",
            str(r["revisions"]),
        ]
        for r in rows
    ]
    widths = [
        max(len(h), *(len(row[i]) for row in table)) for i, h in enumerate(headers)
    ]
    print("  ".join(h.ljust(widths[i]) for i, h in enumerate(headers)))
    print("  ".join("-" * w for w in widths))
    for row, r in zip(table, rows):
        line = "  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row))
        if r["single_reference"]:
            line += "  (single reference)"
        print(line)

    print()
    if not suggestions:
        print(
            "Suggested follows: none - every duplicate already follows its top-level input."
        )
        return
    print("Suggested follows:")
    for s in suggestions:
        if s["declaration"] is None:
            print(f"  # {s['comment']}")
        else:
            print(f"  {s['declaration']}  # {s['comment']}")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--lock",
        default="flake.lock",
        help="flake.lock to read (default: ./flake.lock)",
    )
    parser.add_argument(
        "--metadata",
        help="read `nix flake metadata --json` output instead, or - for stdin",
    )
    parser.add_argument(
        "--json", action="store_true", help="emit machine-readable JSON"
    )
    parser.add_argument(
        "--fork-owner",
        action="append",
        default=None,
        help="owner whose fork groups with its upstream by repository name (repeatable; "
        "default: nazarewk-iac, nazarewk)",
    )
    parser.add_argument(
        "--single-references",
        action="store_true",
        help="include repositories with a single reference (otherwise skipped)",
    )
    parser.add_argument(
        "--fail-on-suggestions",
        action="store_true",
        help="exit 1 when any follows declaration is missing",
    )
    args = parser.parse_args()

    graph = load_graph(args)
    nodes = graph.get("nodes") or {}
    if "root" not in nodes:
        sys.exit("input graph has no root node")
    _, edges = walk(nodes)
    fork_owners = set(args.fork_owner or ["nazarewk-iac", "nazarewk"])
    rows, suggestions = analyze(nodes, edges, args.single_references, fork_owners)

    if args.json:
        json.dump({"repos": rows, "follows": suggestions}, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print_human(rows, suggestions)

    if args.fail_on_suggestions and any(s["declaration"] for s in suggestions):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
