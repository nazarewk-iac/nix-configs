#!/usr/bin/env python
import argparse
import dataclasses
import functools
import json
import os
import shlex
from pathlib import Path
from typing import Callable, Generator

import sys


@dataclasses.dataclass
class Program:
    source: str
    recursive: bool
    single: bool
    unique: bool
    output: str
    limit: int
    patterns: list[str]

    def __post_init__(self):
        self.paths = [Path(value) / self.sub_path for value in self.env_entries]
        self.globbers: list[Callable[[str], Generator[Path, None, None]]] = [
            path.rglob if self.recursive else path.glob for path in self.paths
        ]

    @functools.cached_property
    def env_entries(self):
        name: str
        *_, name = self.source.rsplit("@", maxsplit=1)
        if os.path.pathsep in name:
            value = name
        else:
            name = name.removeprefix("$")
            value = os.environ.get(name, "")
        return value.split(os.path.pathsep)

    @functools.cached_property
    def sub_path(self):
        sub_path, *_ = self.source.rsplit("@", maxsplit=1)
        return Path(sub_path)

    def iter_matches(self):
        def iter_pattern(pattern: str):
            for globber in self.globbers:
                for match in globber(pattern):
                    yield match, match.resolve()
                    if self.single:
                        return

        for pattern in self.patterns:
            found = False
            for match in iter_pattern(pattern):
                found = True
                yield match
            if not found:
                print(f"{pattern} was not found in {self.source}", file=sys.stderr)

    @functools.cached_property
    def matches(self) -> dict[Path, Path]:
        ret = {}
        occurrences = set()
        for match, resolved in self.iter_matches():
            if 0 <= self.limit <= len(ret):
                return ret
            if self.unique:
                if resolved in occurrences:
                    continue
                occurrences.add(resolved)
            ret[match] = resolved
        return ret

    @classmethod
    def create(cls, args: list[str]):
        source_examples = [
            "applications@XDG_DATA_DIRS",
            "XDG_DATA_DIRS",
            "PATH",
        ]
        source_examples.extend(map(shlex.quote, source_examples[:]))
        source_examples = list({e: None for e in source_examples})

        parser = argparse.ArgumentParser(
            description="A script that helps you find files in $PATH-style variables",
        )
        parser.add_argument(
            "source",
            help=f"Where to look for patterns? examples: {', '.join(source_examples)}",
        )
        parser.add_argument(
            "patterns",
            metavar="GLOB",
            nargs="+",
            help="filename glob patterns to search for",
        )
        parser.add_argument(
            "-R",
            "--recursive",
            action="store_true",
            help="search for patterns recursively",
        )
        parser.add_argument(
            "-m",
            "--multiple",
            action="store_false",
            dest="single",
            help="return all matches for a pattern",
        )
        parser.add_argument(
            "-l",
            "--limit",
            metavar="NUM",
            type=int,
            default=-1,
            help="limit number of results",
        )
        parser.add_argument(
            "-u",
            "--unique",
            action="store_true",
            help="do not return same pattern more than once",
        )
        parser.add_argument(
            "-o",
            "--output",
            choices=[
                "j",
                "json",
                "a",
                "auto",
                "b",
                "both",
                "m",
                "match",
                "r",
                "resolved",
            ],
            default="match",
            help="output formatting",
        )

        args = parser.parse_args(args=args)
        return cls(**args.__dict__)

    @functools.cached_property
    def formatter(self) -> Callable[[Path, Path], str]:
        def fmt_json(m, r):
            return json.dumps({"match": str(m), "resolved": str(r)})

        def fmt_auto(m, r):
            if m.resolve() == r:
                return fmt_match(m, r)
            return fmt_both(m, r)

        def fmt_both(m, r):
            return f"{m} -> {r}"

        def fmt_match(m, r):
            return str(m)

        def fmt_resolved(m, r):
            return str(r)

        match self.output:
            case "j" | "json":
                return fmt_json
            case "a" | "auto":
                return fmt_auto
            case "b" | "both":
                return fmt_both
            case "m" | "match":
                return fmt_match
            case "r" | "resolved":
                return fmt_resolved
            case _:
                sys.exit(1)

    def run(self):
        for match, resolved in self.matches.items():
            print(self.formatter(match, resolved))


def main():
    Program.create(sys.argv[1:]).run()


if __name__ == "__main__":
    main()
