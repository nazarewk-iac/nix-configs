import dataclasses
import json
import os
import shutil
import subprocess
from pathlib import Path

import anyio
import itertools
import structlog

from .json_types import Result

logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@dataclasses.dataclass
class Klog:
    binary: Path = dataclasses.field(default_factory=lambda: Path(shutil.which("klog")))

    async def cmd(self, *args: str, **kwargs):
        kwargs.setdefault("stdout", subprocess.PIPE)
        kwargs.setdefault("stderr", None)
        kwargs.setdefault("check", True)
        arguments = list(map(str, itertools.chain([self.binary], args)))
        logger.info("running async command", argv=arguments)
        return await anyio.run_process(arguments, **kwargs)

    async def to_json(self, *inputs: Path | str | bytes):
        paths = [e for e in inputs if e.__class__ is Path]
        pieces = [
            e.encode() if isinstance(e, str) else e
            for e in inputs
            if e and e.__class__ is not Path
        ]

        if not pieces and not paths:
            paths.append(os.devnull)
        data = b"\n\n".join(pieces)
        proc = await self.cmd("json", *paths, input=data)
        raw = json.loads(proc.stdout)
        return Result.load(raw)
