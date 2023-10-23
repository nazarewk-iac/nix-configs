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
class Result:
    source: str
    match: Path
    resolved: Path = dataclasses.field(init=False)

    def __post_init__(self):
        self.resolved = self.match.resolve()

    def __str__(self):
        return self.__format__("auto")

    def __format__(self, format_spec):
        match format_spec:
            case "j" | "json":
                return json.dumps(
                    {
                        "source": self.source,
                        "match": str(self.match),
                        "resolved": str(self.resolved),
                    }
                )
            case "a" | "auto":
                if self.match == self.resolved:
                    return str(self.resolved)
                return f"{self.match} -> {self.resolved}"
            case "b" | "both":
                return f"{self.match} -> {self.resolved}"
            case "m" | "match":
                return str(self.match)
            case "r" | "resolved":
                return str(self.resolved)
            case _:
                raise ValueError(f"Unknown formatter: {format_spec}")


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

    def iter_matches(self) -> Generator[Result, None, None]:
        def iter_pattern(pattern: str):
            for globber in self.globbers:
                for match in globber(pattern):
                    yield Result(source=self.source, match=match)
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
    def results(self) -> list[Result]:
        ret = []
        occurrences = set()
        for result in self.iter_matches():
            if 0 <= self.limit <= len(ret):
                break
            if self.unique:
                if result.resolved in occurrences:
                    continue
                occurrences.add(result.resolved)
            ret.append(result)
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

    def run(self):
        for result in self.results:
            print(f"{result:{self.output}}")


def main():
    Program.create(sys.argv[1:]).run()


if __name__ == "__main__":
    main()
