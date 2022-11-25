import click
import structlog

from . import configure

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@click.group(
    context_settings={"show_default": True},
)
def main():
    ...


if __name__ in ("__main__", "__mp_main__"):
    main()
