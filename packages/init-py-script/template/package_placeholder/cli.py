import functools
import logging
import os
import shlex
import subprocess

import fire
import structlog

PROGRAM = "package-placeholder"
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

    @functools.cached_property
    def _private_dynamic_var(self):
        self._log.warning("Hello private & dynamic var!")
        return None

    @functools.cached_property
    def dynamic_var(self):
        self._log.warning("Hello dynamic var!")
        return None

    def __call__(self):
        self._log.warning("Hello command root!")

    def sub(self):
        self._log.warning("Hello sub-command!")


def main():
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
    fire.Fire(CLI(), name=PROGRAM)


if __name__ == "__main__":
    main()
