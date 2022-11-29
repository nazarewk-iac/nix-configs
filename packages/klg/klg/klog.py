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
import pendulum
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

    async def stop(self, path, *args):
        return await self.cmd("stop", *args, path)

    async def find_latest(self, path, *args, range=False, closed=False):
        result = await self.to_json(path, args=["--sort=desc", *args])
        for record in result.records:
            for entry in record.entries:
                if closed and isinstance(entry, dto.OpenRange):
                    raise KlgException("A range is already opened")
                if range and not isinstance(entry, dto.Range):
                    continue
                return entry
        raise KlgException("No entry was found")

    async def resume(self, path, *args):
        latest = await self.find_latest(path, *args, range=True, closed=True)
        return await self.cmd("start", f"--summary={latest.summary}", *args, path)

    async def plan_month(self, path, hours: int, day_summary: str,
                         now: pendulum.DateTime = None,
                         period: pendulum.DateTime = None,
                         off_tags: set = None,
                         manual_tags: set = None,
                         weekend_tag="#off=weekend",
                         ):
        now = now or pendulum.now()
        period = period or now
        if off_tags is None:
            off_tags = {"#off"}
        if manual_tags is None:
            manual_tags = {"#planner=manual"}
        off_tags.add(weekend_tag)
        plan_mins = hours * 60
        result = await self.to_json(path, args=[f"--period={period.to_date_string()[:-3]}"])

        def grouper(rec: dto.Record):
            return pendulum.parse(rec.date)

        by_date: dict[pendulum.DateTime, list[dto.Record]] = dict(sorted(itertools.groupby(result.records, grouper)))

        # TODO: going by each day of the month make sure:
        #   1) weekends are marked
        #   2) dates have a should set
        #   3) should is raised to total
        # TODO: calculate remaining time to be assigned for future date of the month
        #   - calculate manual_tags, but don't touch values
        #   - skip days with `off_tags`
        #   - distribute the should equally among all days
        can_modify = False
        planned_mins = sum(rec.should_total_mins for rec in result.records)

        for date, records in by_date.items():
            assert len(records) == 1
            record = records[0]
            can_modify = date.date() > now.date()
