#!/usr/bin/env python
import argparse
import io
import subprocess

import networkx as nx
from networkx.drawing.nx_pydot import read_dot

"""
Color legend: black     = Requires
              dark blue = Requisite
              gold      = BindsTo
              dark grey = Wants
              red       = Conflicts
              green     = After
"""
color_to_relation = {
    "black": "Requires",
    "darkblue": "Requisite", # dark blue
    "gold": "BindsTo",
    "grey66": "Wants", # dark grey
    "red": "Conflicts",
    "green": "After",
}


def main():
    parser = argparse.ArgumentParser(description="Finds cycles in systemd units. "
                                                 "Based on https://github.com/jantman/misc-scripts/blob/1ef3d280b399071587f66c9dad50b8ce5b134845/dot_find_cycles.py "
                                                 "by Jason Antman <http://blog.jasonantman.com>")
    parser.add_argument('systemd_args', nargs='*', default=["--order"])
    args = parser.parse_args()

    dot = subprocess.check_output(["systemd-analyze", "dot", "--no-pager", *args.systemd_args], encoding="utf8")
    G = nx.DiGraph(read_dot(io.StringIO(dot)))

    C = nx.simple_cycles(G)

    for first, *rest in C:
        pieces = [first]
        prv = first
        for cur in rest:
            pieces.append(edge_to_str(G, prv, cur))
            pieces.append(cur)
            prv = cur
        pieces.extend(["->", first])
        print(" ".join(pieces))


def edge_to_str(G, start, end):
    edge = G.edges[start, end]
    pieces = []
    edge_color = edge.get("color", "").strip('"')
    relation = color_to_relation.get(edge_color, edge_color)
    if relation:
        pieces.append(relation)
    txt = ", ".join(pieces)
    return f"-{txt}-"


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass  # eat CTRL+C so it won't show an exception
