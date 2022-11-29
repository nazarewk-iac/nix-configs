import dataclasses
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Iterable

import anyio
import cache
import itertools
import structlog

from . import dto

logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@dataclasses.dataclass
class Klog:
    binary: Path = dataclasses.field(default_factory=lambda: Path(shutil.which("klog")))

    async def cmd(self, *args: str, **kwargs):
        kwargs.setdefault("stdout", subprocess.PIPE)
        kwargs.setdefault("stderr", None)
        kwargs.setdefault("check", True)
        arguments = list(map(str, itertools.chain([self.binary], args)))
        logger.debug("running async command", argv=arguments)
        return await anyio.run_process(arguments, **kwargs)

    async def prepare_data(self, inputs: Iterable[Path | str | bytes]):
        async def gen():
            entry: Path | str | bytes
            for entry in inputs:
                if isinstance(entry, bytes):
                    entry = entry.decode()

                if isinstance(entry, str) and entry.startswith("@"):
                    entry = await self.bookmark(entry)

                if isinstance(entry, Path):
                    entry = entry.read_bytes()

                if isinstance(entry, str):
                    entry = entry.encode()

                match entry:
                    case bytes():
                        yield entry
                    case _:
                        raise ValueError(f"Invalid input type: {entry!r}")

                yield b""

        data = []
        async for out in gen():
            data.append(out)
        return b"\n".join(data)

    @cache.AsyncTTL()
    async def bookmark(self, name: str):
        if not name.startswith("@"):
            name = f"@{name}"
        proc = await self.cmd("bookmark", "info", name)
        return Path(proc.stdout.decode()[:-1])

    @cache.AsyncTTL()
    async def bookmarks(self) -> dict[str, Path]:
        proc = await self.cmd("bookmark", "list")
        return {
            (pieces := line.decode().split(" -> "))[0]: Path(pieces[1])
            for line in proc.stdout.splitlines(False)
            if line
        }

    async def to_json(self, *inputs: Path | str | bytes, args: list = None, raise_for_errors=True):
        args = args or []
        data = await self.prepare_data(inputs)
        if not data:
            args.append(os.devnull)
        proc = await self.cmd("json", *args, input=data)
        raw = json.loads(proc.stdout)
        lines = data.decode().splitlines(False)
        result = dto.Result.load({
            "lines": lines,
            "errors": [
                {"lines": lines, **err}
                for err in raw.pop("errors") or []
            ],
            **raw,
        })
        if raise_for_errors:
            result.raise_errors()
        return result
