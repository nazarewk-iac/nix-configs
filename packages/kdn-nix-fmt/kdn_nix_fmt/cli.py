import logging
import os
import shlex
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Callable

import fire
import structlog

PROGRAM = "kdn-nix-fmt"
logger: structlog.stdlib.BoundLogger = structlog.get_logger(PROGRAM)


def run(what, cmd, log=logger, **kwargs):
    kwargs.setdefault("check", True)
    args = list(map(str, cmd))
    log.info(f"{what}", cmd=shlex.join(args))
    return subprocess.run(
        args,
        **kwargs,
    )


class CLI:
    def __init__(self):
        self._log = logger
        self._formatters_cache: dict[Path, Callable[..., None]] = {}
        self.default_formatter = self.alejandra
        self.remotes_formatters = {
            "github.com/nazarewk-iac/": self.alejandra,
            "github.com/nixos/": self.nixfmt,
            "github.com/nix-community/": self.nixfmt,
        }

    def alejandra(self, *args):
        run(f"format with alejandra", ["alejandra", *args])

    def nixfmt(self, *args):
        run(f"format with nixfmt", ["nixfmt", *args])

    def _get_formatter(self, file: Path):
        for root, formatter in self._formatters_cache.items():
            if file.is_relative_to(root):
                return formatter

        log = self._log
        proc = run(
            "determine git root",
            ["git", "rev-parse", "--show-toplevel"],
            log=log,
            capture_output=True,
            check=False,
        )
        if proc.returncode:
            log.info(
                "determining git root failed, falling back to default formatter",
                formatter=self.default_formatter,
            )
            self._formatters_cache[file.parent] = self.default_formatter
            return self.default_formatter

        git_root = Path(proc.stdout[:-1].decode())
        log = log.bind(git_root=git_root)
        if git_root in self._formatters_cache:
            return self._formatters_cache[git_root]

        proc = run(
            "determine git remotes",
            ["git", "rev-parse", "--show-toplevel"],
            log=log,
            capture_output=True,
            check=False,
        )
        remotes = {
            " ".join(line.split()[1:-1]).removeprefix("https://").removesuffix(".git")
            for line in proc.stdout.decode().lower().splitlines()
        }
        for known_remote, formatter in self.remotes_formatters.items():
            for remote in remotes:
                if known_remote in remote:
                    self._formatters_cache[git_root] = formatter
                    return formatter

        return self.default_formatter

    def __call__(self, *files):
        by_formatter = defaultdict(list)

        for file in map(Path, files):
            formatter = self._get_formatter(file)
            by_formatter[formatter].append(file)

        for formatter, files in by_formatter.items():
            formatter(*files)


def main():
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
    fire.Fire(CLI(), name=PROGRAM)


if __name__ == "__main__":
    main()
