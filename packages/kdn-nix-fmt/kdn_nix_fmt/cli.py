"""Format Nix files with `nixfmt`, the same formatter `nix fmt` runs.

The repository used to choose between `alejandra` and `nixfmt` by git remote. `treefmt.nix` names
`nixfmt` for every Nix file, so this wrapper has one tool: a second Nix formatter would rewrite the
same bytes in a different style and `nix fmt` would flip them back.
"""

import logging
import os
import shlex
import subprocess

import fire
import structlog

PROGRAM = "kdn-nix-fmt"
logger: structlog.stdlib.BoundLogger = structlog.get_logger(PROGRAM)


def run(cmd, log=logger, **kwargs):
    kwargs.setdefault("check", True)
    args = list(map(str, cmd))
    log.info("format with nixfmt", cmd=shlex.join(args))
    return subprocess.run(args, **kwargs)


class CLI:
    """Format the given paths in place. With no path, read stdin and write stdout."""

    def __call__(self, *files):
        # `-` is nixfmt's own stdin marker, so it passes through like any other path.
        run(["nixfmt", *files])


def main():
    log_level = getattr(logging, (os.environ.get("LOG_LEVEL") or "INFO").upper())
    logging.basicConfig(format="%(message)s", level=log_level)
    structlog.stdlib.recreate_defaults(log_level=None)
    fire.Fire(CLI(), name=PROGRAM)


if __name__ == "__main__":
    main()
