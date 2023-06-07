import dataclasses
import itertools
import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Iterable

import anyio
import cache
import structlog

from . import dto

logger: structlog.stdlib.BoundLogger = structlog.get_logger()


class KlgException(Exception):
    pass


@dataclasses.dataclass
class Klog:
    binary: Path = dataclasses.field(default_factory=lambda: Path(shutil.which("klog")))

    async def cmd(self, *args: str, **kwargs):
        kwargs.setdefault("stdout", subprocess.PIPE)
        kwargs.setdefault("stderr", None)
        kwargs.setdefault("check", True)
        arguments = list(map(str, itertools.chain([self.binary], args)))
        logger.debug("running async command", command=shlex.join(arguments))
        return await anyio.run_process(arguments, **kwargs)

    async def resolve_path(self, entry: Path | str | bytes):
        if isinstance(entry, bytes):
            entry = entry.decode()

        if isinstance(entry, str):
            if entry.startswith("@"):
                logger.debug("resolving bookmark")
                return await self.bookmark(entry)
            return Path(entry)
        return entry

    async def prepare_data(self, inputs: Iterable[Path | str | bytes]):
        async def gen():
            entry: Path | str | bytes
            for entry in inputs:
                if isinstance(entry, bytes):
                    entry = entry.decode()

                if isinstance(entry, str) and entry.startswith("@"):
                    entry = await self.resolve_path(entry)

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

    async def to_json(
        self, *inputs: Path | str | bytes, args: list = None, raise_for_errors=True
    ):
        args = args or []
        data = await self.prepare_data(inputs)
        if not data:
            args.append(os.devnull)
        proc = await self.cmd("json", *args, input=data)
        raw = json.loads(proc.stdout)
        lines = data.decode().splitlines(keepends=False)
        result = dto.Result.load(
            {
                "lines": lines,
                "errors": [{"lines": lines, **err} for err in raw.pop("errors") or []],
                **raw,
            }
        )
        if raise_for_errors:
            result.raise_errors()
        return result

    async def stop(self, path, *args):
        return await self.cmd("stop", *args, path)

    async def report(self, path, *args):
        proc = await self.cmd("report", "--diff", "--now", "--fill", *args, path)
        return proc.stdout.decode()

    async def day_summary(self, path, *args):
        proc = await self.cmd("today", "--diff", "--now", *args, path)
        return proc.stdout.decode()

    async def find_latest(self, path, *args, range=False, closed=False):
        def entry_sort_key(e: dto.GenericEntry):
            if start_mins := getattr(e, "start_mins", None):
                return [0, -start_mins]
            return [1, 0]

        result = await self.to_json(path, args=["--sort=desc", *args])
        for record in result.records:
            for entry in sorted(record.entries, key=entry_sort_key):
                if closed and isinstance(entry, dto.OpenRange):
                    raise KlgException("A range is already opened")
                if range and not isinstance(entry, dto.Range):
                    continue
                return record, entry
        raise KlgException("No entry was found")

    async def resume(self, path, *args):
        _, latest = await self.find_latest(path, *args, range=True, closed=True)
        return await self.cmd("start", f"--summary={latest.summary}", *args, path)
