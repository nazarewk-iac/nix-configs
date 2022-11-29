import difflib
from pathlib import Path

import anyio
import click
import structlog

from . import configure
from .klog import Klog

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@click.group(
    context_settings={"show_default": True},
)
def main():
    ...


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
    if diff:
        if diff_content:
            print(diff_content, end="")
        else:
            print(f"OK: {path}")

    if check and diff_content:
        raise click.ClickException("File is not formatted.")

    if diff_content and write:
        path.write_text(formatted)


if __name__ in ("__main__", "__mp_main__"):
    main()
