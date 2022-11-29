from __future__ import annotations
import csv
import dataclasses
import datetime
import difflib
import functools
import shutil
import subprocess
import time
import tomllib
from collections import defaultdict
from pathlib import Path

import anyio
import click
import dacite
import pendulum
import structlog
import xdg

from . import configure, dto
from .klog import Klog

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()

CONFIG: Config = None


@dataclasses.dataclass
class TagMapping:
    tag: str
    value: str


@dataclasses.dataclass
class TagToFieldMapping:
    field: str
    mappings: list[TagMapping]


@dataclasses.dataclass
class ReportConfig:
    resource: str = ""
    tags: list[str] = dataclasses.field(default_factory=list)
    fields: list[TagToFieldMapping] = dataclasses.field(default_factory=dict)

    def map_tags(self, tags: set[str]):
        ret = {}
        for entry in self.fields:
            field_name = entry.field
            mappings = entry.mappings
            if not mappings[-1].tag:
                ret[field_name] = mappings[-1].value
            else:
                ret[field_name] = ""
            for mapping in mappings:
                if mapping.tag in tags:
                    ret[field_name] = mapping.value
                    break
        return ret


@dataclasses.dataclass
class Config:
    reports: dict[str, ReportConfig] = dataclasses.field(default_factory=dict)

    @classmethod
    def load(cls, data: dict):
        return dacite.from_dict(cls, data)


@click.group(
    context_settings={"show_default": True},
)
@click.option("--config", default=xdg.xdg_config_home() / "klg" / "config.toml")
def main(config):
    config = Path(config)
    global CONFIG
    data = {}
    if config.exists():
        data = tomllib.loads(config.read_text())
    CONFIG = Config.load(data)


@main.command()
@click.argument("path", default="@default")
@click.option("--check/--no-check", is_flag=True)
@click.option("--diff/--no-diff", is_flag=True, default=True)
@click.option("--write/--no-write", is_flag=True, default=True)
def fmt(path, check, diff, write):
    klog = Klog()
    if path.startswith("@"):
        path = anyio.run(klog.bookmark, path)
    else:
        path = Path(path)

    assert path.exists()

    result = anyio.run(klog.to_json, path)
    formatted = format(result, "klg")
    diff_content = result.diff(formatted)
    if diff_content:
        if diff:
            print(diff_content, end="")
    else:
        print(f"OK: {path}")

    if check and diff_content:
        raise click.ClickException("File is not formatted.")

    if diff_content and write:
        path.write_text(formatted)


@main.command()
@click.option("--resource", default="")
@click.option("-p", "--period", default=pendulum.now().to_date_string()[:-3],
              help="Records in period: YYYY (year), YYYY-MM (month), YYYY-Www (week), or YYYY-Qq (quarter)")
@click.option("-t", "--tag", "tags", multiple=True,
              help="Records (or entries) that match these tags")
@click.option("-o", "--output", default="", help="Where to store csv/xlsx file?")
@click.option("-r", "--report", "report_name", default="default")
@click.argument("paths", nargs=-1)
def report(paths, period, tags, output, report_name, resource):
    klog = Klog()
    cfg = CONFIG.reports.get(report_name, ReportConfig())
    cfg.resource = resource or cfg.resource
    cfg.tags = tags or cfg.tags
    paths = paths or ["@default"]
    paths = [
        Path(raw) if not raw.startswith("@") else anyio.run(klog.bookmark, raw)
        for raw in paths
    ]
    args = [f"--period={period}"]

    if output:
        output = Path(output)
    else:
        assert len(paths) == 1
        path = paths[0]
        output = path.with_name(f"{period}_report_{report_name}.csv")

    if tags:
        args.append(f"--tag={','.join(tags)}")

    fn = functools.partial(klog.to_json, *paths, args=args)
    result: dto.Result = anyio.run(fn)

    rows = [
        ("Resource Name", "Date", "Time spent", "Minutes", "Summary", *cfg.map_tags(set()))
    ]

    for record in result.records:
        for entry in record.entries:
            row = [
                cfg.resource,
                record.date,
                entry.total,
                entry.total_mins,
                entry.summary.strip(),
            ]
            tagged_values = cfg.map_tags(set(record.tags) | set(entry.tags))
            for name, value in tagged_values.items():
                row.append(value)
            rows.append(row)

    total_mins = sum(r.total_mins for r in result.records)
    rows.append((
        "total",
        "",
        dto.Base.format_duration(total_mins),
        total_mins,
    ))

    expected_mins = sum(r.should_total_mins for r in result.records)
    rows.append((
        "expected",
        "",
        dto.Base.format_duration(expected_mins),
        expected_mins,
    ))
    diff_mins = sum(r.diff_mins for r in result.records)
    rows.append((
        "difference",
        "",
        dto.Base.format_duration(diff_mins),
        diff_mins,
    ))

    with output.open("w") as f:
        writer = csv.writer(f)
        writer.writerows(rows)

    if not shutil.which("libreoffice"):
        print(output)
        return

    converted = output.with_suffix(".xlsx")
    subprocess.run([
        "libreoffice",
        "--headless",
        "--convert-to", converted.suffix[1:],
        "--outdir", output.parent,
        output,
    ], check=True)
    print(converted)


if __name__ in ("__main__", "__mp_main__"):
    main()
