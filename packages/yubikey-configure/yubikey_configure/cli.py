import json
import re
import shutil
import subprocess
from pathlib import Path

import click
import structlog
from structlog.contextvars import bind_contextvars, bound_contextvars

from . import configure

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()

PASS: Path
YKMAN: Path

terminal_escape_code = re.compile(r"\x1b[^m]*m")


def path_setter(name: str, required=True):
    def setter(ctx: click.Context, param: click.Parameter, value):
        if not value and required:
            raise click.BadParameter(f"{param.name} not found!")
        globals()[name] = Path(value).absolute()

    return setter


def populate_secrets(target: str, reset=False, **defaults):
    path = Path("yubikeys") / target
    defaults = {k: v for k, v in defaults.items() if v}
    data = dict(defaults)

    # load current store data
    pass_ls_prefix = "└── "
    proc = subprocess.run(
        [PASS, "ls", path],
        check=False,
        stdout=subprocess.PIPE,
        encoding="utf8"
    )
    lines = proc.stdout.splitlines(False)
    if proc.returncode == 0 and reset:
        logger.warning(f"resetting {path}")
        subprocess.run(
            [PASS, "rm", "--recursive", "--force", path],
            check=True,
        )
        lines = []

    loaded_data = {}
    for line in lines:
        key = line.removeprefix(pass_ls_prefix)
        if line != key:
            continue
        proc = subprocess.run(
            [PASS, "show", path / key],
            check=True,
            stdout=subprocess.PIPE,
            encoding="utf8"
        )
        # pass adds a newline at the end
        value = proc.stdout[:-1]
        if not value:
            continue
        loaded_data[key] = data[key] = value

    # store defaults in password-store
    for key, value in defaults.items():
        if loaded_data.get(key, ""):
            continue

        logger.info(f"Inserted default {path / key} into password-store.")
        subprocess.run(
            [PASS, "insert", "--force", path / key],
            input=f"{value}\n" * 2,
            check=True,
            encoding="utf8",
        )

    pins = {
        "gpg-pin": 6,
        "gpg-admin-pin": 8,
        "gpg-reset-code": 8,
    }

    for key, length in pins.items():
        with bound_contextvars(key=key, path=str(path/key)):
            if data.get(key, ""):
                continue
            logger.info(f"generating new secret")
            proc = subprocess.run(
                [PASS, "generate", path / key, str(length)],
                check=True,
                stdout=subprocess.PIPE,
                encoding="utf8",
            )
            value = proc.stdout.splitlines(False)[-1]
            value = terminal_escape_code.sub("", value)
            # pass adds a newline at the end
            data[key] = value

    return data


@click.command(
    context_settings={"show_default": True},
)
@click.option("-t", "--target")
@click.option("-c", "--config-target", default="")
@click.option("--gpg-pin", default="")
@click.option("--gpg-admin-pin", default="")
@click.option("--gpg-reset-code", default="")
@click.option("--reset/--no-reset", default=False)
@click.option("--pass-bin", default=shutil.which("pass"), callback=path_setter("PASS"), expose_value=False)
@click.option("--ykman-bin", default=shutil.which("ykman"), callback=path_setter("YKMAN"), expose_value=False)
def main(target, config_target, **configs):
    config_target = config_target or target
    bind_contextvars(config_target=config_target)

    secrets = populate_secrets(config_target, **{
        k.replace("_", "-"): v
        for k, v in configs.items()
    })
    logger.info(json.dumps(secrets, indent=2))
    bind_contextvars(target=target)

    cmd = [YKMAN, f"--device={target}"]
    subprocess.run([*cmd, "info"], check=True)
    subprocess.run([*cmd, "openpgp", "info"], check=True)


if __name__ == "__main__":
    _kwargs = dict(
        auto_envvar_prefix="YC",
    )
    main(**_kwargs)
