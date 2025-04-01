from __future__ import annotations

import tempfile

import asyncclick as click
import csv
import datetime
import functools
import pendulum
import shutil
import structlog
import subprocess
import textwrap
import tomllib
import xdg_base_dirs
from pathlib import Path

from . import configure, dto
from .config import Config, ReportConfig, TagsType, ReportType
from .klog import Klog

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()

CONFIG: Config = None


async def get_profile_path(
    klog: Klog,
    config: Config,
    path: str = "",
    profile: str = None,
) -> Path:
    if not path:
        # TODO: change to using multiple paths
        path = next(config.profile_paths(id=profile))
    else:
        path = await klog.resolve_path(path)

    assert path.exists(), path
    return path


@click.group(
    context_settings={"show_default": True},
)
@click.option("--profile", "-p", default="")
@click.option(
    "--config", default=xdg_base_dirs.xdg_config_home() / "klg" / "config.toml"
)
async def main(config, profile):
    config = Path(config).resolve()
    global CONFIG
    data = {}
    if config.exists():
        data = tomllib.loads(config.read_text())
    data["path"] = config
    if profile:
        data["selected_profile"] = profile
    CONFIG = Config.load(data)


@main.group()
async def entry():
    pass


@entry.command()
@click.option("-p", "--path", default="")
async def latest(path):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)

    record, entry = await klog.find_latest(path)
    click.echo(record.date)
    click.echo(textwrap.indent(entry.format(), "  "))


def format_result(result: dto.Result):
    formatted = format(result, "klg")
    diff_content = result.diff(formatted)
    return formatted, diff_content


@main.command()
@click.option("-p", "--path", default="")
@click.option("--check/--no-check", is_flag=True)
@click.option("--sort/--no-sort", is_flag=True, default=True)
@click.option("-d", "--sort-cutoff-days", default=3)
@click.option("--diff/--no-diff", is_flag=True, default=True)
@click.option("--write/--no-write", is_flag=True, default=True)
async def fmt(path, check, diff, write, sort, sort_cutoff_days):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)

    result = await klog.to_json(path)

    if sort:
        cutoff = pendulum.now() + datetime.timedelta(days=sort_cutoff_days)
        result.records.sort(
            key=lambda r: (
                not (bool(r.entries) or r.date_datetime < cutoff),
                -r.date_datetime.int_timestamp,
            )
        )

    formatted, diff_content = format_result(result)
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
@click.option(
    "-p",
    "--period",
    default=pendulum.now().to_date_string()[:-3],
    help="Records in period: YYYY (year), YYYY-MM (month), YYYY-Www (week), or YYYY-Qq (quarter)",
)
@click.option(
    "-t",
    "--tag",
    "tags",
    multiple=True,
    help="Records (or entries) that match these tags",
)
@click.option("-o", "--output", default="", help="Where to store csv/xlsx file?")
@click.option("-r", "--report", "report_id", default="default")
@click.option("--diff/--no-diff", default=False)
@click.argument("paths", nargs=-1)
async def generate_report(paths, period, tags, output, report_id, resource, diff):
    klog = Klog()
    profile = CONFIG.get_profile()
    if report_id != "default" and report_id not in profile.reports:
        raise click.ClickException(
            f"Unknown report id {report_id}, available reports are: {', '.join(profile.reports)}"
        )
    report = profile.reports.get(report_id, ReportConfig())
    report.resource = resource or report.resource
    report.tags = tags or report.tags
    report.name = report.name or f"{profile.name}-{report_id}"

    paths = paths or [""]
    paths = [
        await get_profile_path(klog, CONFIG, raw, profile=profile.name) for raw in paths
    ]
    args = [f"--period={period}"]

    if output:
        output = Path(output)
    else:
        assert len(paths) == 1
        path = paths[0]
        output = path.with_name(f"{period}_report_{report.name}.csv")

    if tags:
        args.append(f"--tag={','.join(tags)}")

    fn = functools.partial(klog.to_json, *paths, args=args)
    result: dto.Result = await fn()

    rows = [
        (
            "Resource Name",
            "Date",
            "Time spent",
            "Minutes",
            "Summary",
            *report.headers,
        )
    ]
    fields_totals = {key: 0.0 for key in report.headers}
    match report.type:
        case ReportType.daily:
            for record in result.records:
                summaries = {record.summary: True}
                total_minutes = 0
                fields = report.map_tags(
                    value=1.0,
                    type=TagsType.record,
                    record_tags=record.tags,
                )
                for entry in record.entries:
                    total_minutes += entry.current_minutes
                    if entry.summary:
                        summaries[entry.summary] = True
                    entry_fields = report.map_tags(
                        value=entry.current_hours,
                        type=TagsType.entry,
                        entry_tags=entry.tags,
                        record_tags=record.tags,
                    )
                    for key, value in entry_fields.items():
                        match value:
                            case str():
                                if fields[key].strip():
                                    fields[key] = f"{fields[key]}\n{value}"
                            case float() | int():
                                fields[key] += value

                for key, value in fields.items():
                    if isinstance(value, float):
                        fields_totals[key] += value

                row = [
                    report.resource,
                    record.date,
                    dto.Base.format_duration(total_minutes),
                    total_minutes,
                    "\n".join(summaries),
                    *fields.values(),
                ]
                rows.append(row)
        case ReportType.complete:
            for record in result.records:
                rows.append(
                    [
                        report.resource,
                        record.date,
                        "0h",
                        0,
                        record.summary.strip(),
                        *report.map_tags(
                            value=1.0,
                            type=TagsType.record,
                            record_tags=record.tags,
                        ).values(),
                    ]
                )
                for entry in record.entries:
                    rows.append(
                        [
                            report.resource,
                            record.date,
                            entry.total,
                            entry.current_minutes,
                            entry.summary.strip(),
                            *report.map_tags(
                                value=entry.current_hours,
                                type=TagsType.entry,
                                entry_tags=entry.tags,
                                record_tags=record.tags,
                            ).values(),
                        ]
                    )

    total_mins = sum(e.current_minutes for r in result.records for e in r.entries)
    rows.append(
        (
            "total",
            "",
            dto.Base.format_duration(total_mins),
            total_mins,
            "",
            *fields_totals.values(),
        )
    )
    if diff:
        expected_mins = sum(r.should_total_mins for r in result.records)
        rows.append(
            (
                "expected",
                "",
                dto.Base.format_duration(expected_mins),
                expected_mins,
            )
        )
        diff_mins = sum(r.diff_mins for r in result.records)
        rows.append(
            (
                "difference",
                "",
                dto.Base.format_duration(diff_mins),
                diff_mins,
            )
        )

    with output.open("w") as f:
        writer = csv.writer(f)
        writer.writerows(rows)

    if not shutil.which("libreoffice"):
        print(output)
        return

    converted = output.with_suffix(".xlsx")
    # run libreoffice with a temporary user profile, so it does not interact with another running instance
    # see https://ask.libreoffice.org/t/how-to-not-connect-to-a-running-instance/534/2
    with tempfile.TemporaryDirectory() as lo_profile:
        subprocess.run(
            [
                "libreoffice",
                f"-env:UserInstallation=file://{lo_profile}",
                "--headless",
                "--convert-to",
                converted.suffix[1:],
                "--outdir",
                output.parent,
                output,
            ],
            check=True,
        )
    print(converted)


@main.command(context_settings={"ignore_unknown_options": True})
@click.option("-p", "--path", default="")
@click.argument("args", nargs=-1)
async def stop(path, args):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)
    await klog.stop(path, *args)
    print(await klog.day_summary(path))


@main.command(context_settings={"ignore_unknown_options": True})
@click.option("-p", "--path", default="")
@click.argument("args", nargs=-1)
async def resume(path, args):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)
    await klog.resume(path, *args)
    print(await klog.day_summary(path))


@main.command(context_settings={"ignore_unknown_options": True})
@click.option("-p", "--path", default="")
@click.argument("args", nargs=-1)
async def switch(path, args):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)
    await klog.switch(path, *args)
    print(await klog.day_summary(path))


@main.command(context_settings={"ignore_unknown_options": True})
@click.option("-p", "--path", default="")
@click.argument("args", nargs=-1)
async def today(path, args):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)
    print(await klog.day_summary(path, *args))


@main.command()
@click.option(
    "-p",
    "--period",
    default=pendulum.now().to_date_string()[:-3],
    help="Records in period: YYYY (year), YYYY-MM (month), YYYY-Www (week), or YYYY-Qq (quarter)",
)
@click.option(
    "-t",
    "--tag",
    "tags",
    multiple=True,
    help="Records (or entries) that match these tags",
)
@click.option("--store/--no-store", default=True)
@click.option("-p", "--path", default="")
@click.argument("args", nargs=-1)
async def report(path, args, period, tags, store):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)
    args = [
        f"--period={period}",
        *args,
    ]
    if tags:
        args.insert(0, f"--tag={','.join(tags)}")

    print(await klog.report(path, *args))

    if store:
        tags_repr = "".join(f"-{t}" for t in tags)
        store_path = path.with_name(f"{period}{tags_repr}.txt")
        store_path.write_text(await klog.report(path, "--no-style", *args))
        logger.info("report stored", path=str(store_path))


@main.command()
@click.option(
    "-P",
    "--period",
    default=pendulum.now().to_date_string()[:-3],
    help="Records in period: YYYY (year), YYYY-MM (month), YYYY-Www (week), or YYYY-Qq (quarter)",
)
@click.option("--write/--no-write", is_flag=True, default=True)
@click.option("-p", "--path", default="")
async def plan_month(period, path, write):
    klog = Klog()
    path = await get_profile_path(klog, CONFIG, path)
    plan = CONFIG.get_profile().plan

    result = await klog.to_json(path)
    result.plan_month(
        monthly_hours=plan.monthly_hours,
        daily_minutes=plan.daily_minutes,
        period=pendulum.parse(period),
        day_off_tags=plan.day_off_tags,
        not_day_off_tags=plan.not_day_off_tags,
        day_skip_tags=plan.day_skip_tags,
        weekend_tag=plan.weekend_tag,
        entry_skip_tags=plan.entry_skip_tags,
    )
    formatted, diff_content = format_result(result)
    if diff_content:
        print(diff_content, end="")
    else:
        print(f"OK: {path}")

    if diff_content and write:
        path.write_text(formatted)


@main.command(name="raw", context_settings={"ignore_unknown_options": True})
@click.option("-p", "--path", default="")
@click.option(
    "--with-path/--without-path",
    "-i/-I",
    "include_path",
    is_flag=True,
    default=False,
)
@click.argument("args", nargs=-1)
async def raw(path, include_path, args):
    klog = Klog()
    include_path = include_path or bool(path)
    path = await get_profile_path(klog, CONFIG, path=path)
    args = [*args]
    if include_path:
        args.append(path)
    await klog.cmd(*args, stdout=None)


if __name__ in ("__main__", "__mp_main__"):
    main(_anyio_backend="trio", auto_envvar_prefix="KLG")
