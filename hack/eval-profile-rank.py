#!/usr/bin/env python3
"""Rank a folded-stack profile that the CppNix evaluation profiler wrote.

Input is one file in collapsed-stack format. Each line holds a semicolon-separated
stack and then a space and a sample count. Each frame reads
`<source>/<relative path>:<line>:<column>[:<name>]`.

Output is four tables on stdout:

  1. The total sample count, and the sample rate the caller states.
  2. Self time per leaf frame. This ranks a cost centre by time.
  3. Self time per file.
  4. Self time per source root. This one is decisive: it counts how many nixpkgs
     copies the evaluation pulls in.

Never rank a cost by call count alone. `NIX_COUNT_CALLS` ranks a cheap hot function
above an expensive one. This script ranks time.

Usage:
    hack/eval-profile-rank.py <file.folded> [--top N]

It reads the standard library only, so a plain `python3` runs it.
"""

import argparse
import collections
import re
import sys

# A flake reference carries a revision, so two profiles of two revisions would show two
# different roots for one input. Drop the revision and keep the identity.
_FLAKE_REV = re.compile(r"«github:([^/»]+)/([^/»]+)/[0-9a-f]{6,}[^»]*»")
_FLAKE_HASH = re.compile(r"«[^»]*narHash[^»]*»")
_STORE = re.compile(r"^/nix/store/[a-z0-9]{32}-")


def normalise(frame: str) -> str:
    """Make one frame stable across two revisions of the same input."""
    frame = _FLAKE_REV.sub(r"«\1/\2»", frame)
    frame = _FLAKE_HASH.sub("«pinned»", frame)
    frame = _STORE.sub("/store:", frame)
    return frame


def file_key(frame: str) -> str:
    """The file part of one frame. It drops the line and the column."""
    frame = normalise(frame)
    match = re.match(r"^(.*?):\d+:\d+", frame)
    return match.group(1) if match else frame


def root_key(frame: str) -> str:
    """The source root of one frame — the flake input or the store path it came from."""
    frame = normalise(frame)
    if frame.startswith("«"):
        end = frame.find("»")
        if end > 0:
            return frame[: end + 1]
        return frame
    if frame.startswith("/store:"):
        rest = frame[len("/store:") :]
        return "/store:" + rest.split("/", 1)[0]
    if ":" not in frame and "/" not in frame:
        # A primop with no source position, for example `primop head`.
        return "<no source position>"
    return frame.split("/", 1)[0] or frame


def table(title: str, counter: collections.Counter, total: int, top: int) -> None:
    print()
    print(f"=== {title} ===")
    for key, value in counter.most_common(top):
        print(f"{value:8d}  {100 * value / total:6.2f}%  {key}")


def main() -> int:
    parser = argparse.ArgumentParser(prog="eval-profile-rank")
    parser.add_argument("folded", help="the collapsed-stack file")
    parser.add_argument("--top", type=int, default=25, help="rows per table, default 25")
    args = parser.parse_args()

    self_leaf: collections.Counter = collections.Counter()
    self_file: collections.Counter = collections.Counter()
    self_root: collections.Counter = collections.Counter()
    incl_file: collections.Counter = collections.Counter()
    total = 0

    with open(args.folded, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            cut = line.rfind(" ")
            if cut < 0:
                continue
            try:
                count = int(line[cut + 1 :])
            except ValueError:
                continue
            stack = line[:cut]
            frames = stack.split(";")
            total += count
            leaf = frames[-1]
            self_leaf[normalise(leaf)] += count
            self_file[file_key(leaf)] += count
            self_root[root_key(leaf)] += count
            for key in {file_key(frame) for frame in frames}:
                incl_file[key] += count

    if total == 0:
        print("no samples — the profile is empty", file=sys.stderr)
        return 1

    print(f"TOTAL SAMPLES: {total}")
    print(f"At 99 Hz that is about {total / 99.0:.1f} s of sampled evaluation.")
    table("SELF TIME by leaf frame", self_leaf, total, args.top)
    table("SELF TIME by file", self_file, total, args.top)
    table("SELF TIME by source root", self_root, total, args.top)
    table("INCLUSIVE by file (the stack holds the file)", incl_file, total, args.top)
    return 0


if __name__ == "__main__":
    sys.exit(main())
