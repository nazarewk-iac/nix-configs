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
@click.option("--check", is_flag=True)
@click.option("--diff/--no-diff", is_flag=True, default=True)
def fmt(path, check, diff):
    klog = Klog()
    if path.startswith("@"):
        path = anyio.run(klog.bookmark, path)
    else:
        path = Path(path)

    assert path.exists()

    result = anyio.run(klog.to_json, path)
    formatted = format(result, "klg")
    if check or diff:
        diff_content = "".join(difflib.ndiff(
            list(f"{line}\n" for line in result.lines),
            formatted.splitlines(keepends=True)
        ))
        if diff:
            print(diff_content, end="")

        if check and diff_content:
            raise click.ClickException("File is not formatted.")

    path.write_text(formatted)


if __name__ in ("__main__", "__mp_main__"):
    main()
