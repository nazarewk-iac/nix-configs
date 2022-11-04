import structlog
import click

from . import configure

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@click.command(
    context_settings={"show_default": True},
)
def main():
    logger.warning("Hello, world!", has_trio=False)


if __name__ == "__main__":
    main()
