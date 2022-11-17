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
GPG: Path

terminal_escape_code = re.compile(r"\x1b[^m]*m")


def path_setter(name: str, required=True):
    def setter(ctx: click.Context, param: click.Parameter, value):
        if not value and required:
            raise click.BadParameter(f"{param.name} not found!")
        globals()[name] = Path(value).absolute()

    return setter


def pass_get(path: Path):
    proc = subprocess.run(
        [PASS, "show", path],
        stdout=subprocess.PIPE,
        check=True,
        encoding="utf8"
    )
    # pass adds a newline at the end
    return proc.stdout[:-1]


def pass_set(path: Path, value: str):
    subprocess.run(
        [PASS, "insert", "--force", path],
        input=f"{value}\n" * 2,
        check=True,
        encoding="utf8",
    )


def populate_secrets(target: str, regenerate=False, **defaults):
    target_path = Path("yubikeys") / target
    defaults = {k: v for k, v in defaults.items() if v}
    data = dict(defaults)

    # load current store data
    pass_ls_prefix = "└── "
    proc = subprocess.run(
        [PASS, "ls", target_path],
        check=False,
        stdout=subprocess.PIPE,
        encoding="utf8"
    )
    lines = proc.stdout.splitlines(False)
    if proc.returncode == 0 and regenerate:
        logger.warning(f"resetting {target_path}")
        subprocess.run(
            [PASS, "rm", "--recursive", "--force", target_path],
            check=True,
        )
        lines = []

    loaded_data = {}
    for line in lines:
        key = line.removeprefix(pass_ls_prefix)
        if line != key:
            continue
        value = pass_get(target_path / key)
        if not value:
            continue
        loaded_data[key] = data[key] = value

    # store defaults in password-store
    for key, value in defaults.items():
        if loaded_data.get(key, ""):
            continue

        logger.info(f"Inserted default {target_path / key} into password-store.")
        pass_set(target_path / key, value)

    pins = {
        "gpg-pin": 6,
        "gpg-admin-pin": 8,
        "gpg-reset-code": 8,
    }

    for key, length in pins.items():
        with bound_contextvars(key=key, path=str(target_path / key)):
            if data.get(key, ""):
                continue
            logger.info(f"generating new secret")
            proc = subprocess.run(
                [PASS, "generate", target_path / key, str(length)],
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
@click.option("--gpg-fpr", default="")
@click.option("--gpg-passphrase-key", default="gpg-password")
@click.option("--regenerate/--no-regenerate", default=False)
@click.option("--pass-bin", default=shutil.which("pass"), callback=path_setter("PASS"), expose_value=False)
@click.option("--ykman-bin", default=shutil.which("ykman"), callback=path_setter("YKMAN"), expose_value=False)
@click.option("--gpg-bin", default=shutil.which("gpg"), callback=path_setter("GPG"), expose_value=False)
def main(target, config_target, gpg_passphrase_key, gpg_fpr, **configs):
    config_target = config_target or target
    bind_contextvars(config_target=config_target)

    secrets = populate_secrets(config_target, **{
        k.replace("_", "-"): v
        for k, v in configs.items()
    })
    gpg_passphrase = subprocess.run(
        [PASS, "show", gpg_passphrase_key],
        check=True,
        stdout=subprocess.PIPE,
        encoding="utf8"
    ).stdout[:-1]
    logger.info(json.dumps(secrets, indent=2))
    bind_contextvars(target=target)

    cmd = [YKMAN, f"--device={target}"]

    subprocess.run([*cmd, "info"], check=True)

    pgp = [*cmd, "openpgp"]
    subprocess.run([*pgp, "reset"], check=True)
    subprocess.run([*pgp, "info"], check=True)
    subprocess.run([
        *pgp, "access", "change-admin-pin",
        "--admin-pin=12345678",
        f"--new-admin-pin={secrets['gpg-admin-pin']}",
    ],
        check=True)
    subprocess.run([
        *pgp, "access", "change-reset-code",
        f"--admin-pin={secrets['gpg-admin-pin']}",
        f"--reset-code={secrets['gpg-reset-code']}",
    ],
        check=True)
    subprocess.run([
        *pgp, "access", "change-pin",
        "--pin=123456",
        f"--new-pin={secrets['gpg-pin']}",
    ],
        check=True)
    subprocess.run([*pgp, "access", "set-retries", "3", "3", "3"], check=True)

    if not gpg_fpr:
        fprs = {
            line.split()[0]
            for line in subprocess.check_output(
                [GPG, "--list-options", "show-only-fpr-mbox", "--list-secret-keys"],
                encoding='utf8').splitlines(False)
        }
        assert len(fprs) == 1
        gpg_fpr = fprs.pop()


if __name__ == "__main__":
    _kwargs = dict(
        auto_envvar_prefix="YC",
    )
    main(**_kwargs)
