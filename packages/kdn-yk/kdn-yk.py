from __future__ import annotations

import abc
import collections
import contextlib
import dataclasses
import functools
import io
import itertools
import json
import logging as _logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import typing
from pathlib import Path

import click.testing
import fire
import structlog
import ykman
import ykman._cli.__main__
import ykman._cli.piv
import ykman.base
import ykman.piv
import ykman.scripting
import yubikit.core.smartcard
import yubikit.piv
from ykman.device import list_all_devices, scan_devices

PROGRAM = "kdn-yk"
PASS_PREFIX = Path("yubikeys")
logger: structlog.stdlib.BoundLogger = structlog.get_logger(PROGRAM)

# this is required for age-plugin-yubikey, see https://github.com/str4d/age-plugin-yubikey/issues/92
PIV_MANAGEMENT_KEY_TYPE = yubikit.piv.MANAGEMENT_KEY_TYPE.TDES


def get_default_store_dir():
    return Path(os.environ.get("PASSWORD_STORE_DIR") or Path.home() / ".password-store")


class SecretStorage(collections.abc.MutableMapping[Path, bytes], abc.ABC):
    # TODO: implement SOPS storage? pass is finicky with multiple keys plugged in
    @abc.abstractmethod
    def iter(
        self, path: Path, relative=False, keys: tuple[str, ...] = ()
    ) -> typing.Generator[Path, None, None]: ...

    @abc.abstractmethod
    def generate(
        self,
        path: Path,
        length=6,
        symbols=True,
        **kwargs,
    ) -> bytes: ...


@dataclasses.dataclass
class PasswordStore(SecretStorage):
    binary: Path = Path(shutil.which("pass"))
    store_dir: Path = dataclasses.field(default_factory=get_default_store_dir)
    debug: bool = os.environ.get("DEBUG") == "1"

    def cmd(self, args, **kwargs):
        kwargs.setdefault("check", True)
        kwargs.setdefault("stdout", subprocess.PIPE)
        chunks = [[self.binary], args]
        if self.debug:
            chunks.insert(0, ["bash", "-x"])
        cmd = list(map(str, itertools.chain(*chunks)))
        env = {
            **os.environ,
            **kwargs.get("env", {}),
            "PASSWORD_STORE_DIR": str(self.store_dir),
        }
        return subprocess.run(cmd, env=env, **kwargs)

    @staticmethod
    def _coalesce(val: str | bytes) -> bytes:
        if isinstance(val, str):
            val = val.encode()
        return val

    def __iter__(self):
        yield from self.iter(Path("/"))

    def __len__(self):
        return sum(1 for _ in self)

    def __getitem__(self, path: Path) -> bytes:
        file_path = self.store_dir / path.parent / f"{path.name}.gpg"
        if not file_path.exists():
            raise KeyError(f"{file_path=} does not exist")
        # pass adds a newline at the end
        output = self.cmd(["show", path]).stdout[:-1]
        output = self._coalesce(output)
        return output

    def __setitem__(self, path: Path, value: bytes):
        self.cmd(
            ["insert", "--multiline", "--force", path],
            input=b"%s\n" % self._coalesce(value),
        )

    def __delitem__(self, path: Path):
        dir_path = self.store_dir / path
        self.delete(path, recursive=dir_path.is_dir())

    def delete(self, path: Path, recursive=False):
        dir_path = self.store_dir / path
        file_path = self.store_dir / path.parent / f"{path.name}.gpg"
        if not dir_path.is_dir() and not file_path.exists():
            return
        args = ["rm", "--force"]
        if recursive:
            args.append("--recursive")
        self.cmd([*args, path], check=True)

    def iter(
        self, path: Path, relative=False, keys: tuple[str, ...] = ()
    ) -> typing.Generator[Path, None, None]:
        entry: Path
        path = self.store_dir / path
        if keys:
            iterator = (path / f"{key}.gpg" for key in keys)
        else:
            iterator = path.rglob("*.gpg")
        for entry in iterator:
            entry = entry.with_suffix("")
            entry = entry.relative_to(self.store_dir)
            if relative:
                entry = entry.relative_to(path)
            yield entry

    def generate(
        self,
        path: Path,
        length=6,
        symbols=True,
        terminal_escape_codes=re.compile(rb"\x1b[^m]*m"),
    ) -> bytes:
        # see https://git.zx2c4.com/password-store/tree/src/password-store.sh#n561
        args = ["generate"]
        if not symbols:
            args.append("--no-symbols")
        proc = self.cmd(
            [*args, path, str(length)],
            stdout=subprocess.PIPE,
        )
        value = self._coalesce(proc.stdout.splitlines(False)[-1])
        value = terminal_escape_codes.sub(b"", value)
        return value


@dataclasses.dataclass()
class YubiKey:
    serial: int
    storage: SecretStorage
    config_target: str = ""
    s: ykman.scripting.ScriptingDevice = None

    def __post_init__(self):
        self.context_managers: list[typing.ContextManager] = []
        self.s = self._wait_for()
        self.log = logger.bind(
            firmware=str(self.s.info.version),
            config_target=self.config_target,
        )

    def _wait_for(self, interval=3.0):
        state: int | None = None
        while True:
            pids, new_state = scan_devices()
            if new_state == state:
                continue
            state = new_state
            for device, info in list_all_devices():
                if info.serial == self.serial:
                    return ykman.scripting.ScriptingDevice(device, info)

            self.log.info("still waiting", serial=self.serial)
            time.sleep(interval)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        for context_managers in reversed(self.context_managers):
            context_managers.__exit__(exc_type, exc_val, exc_tb)

        for key in ["sc"]:
            if key in self.__dict__:
                delattr(self, key)

    @functools.cached_property
    def pass_prefix(self):
        return PASS_PREFIX / self.config_target

    @functools.cached_property
    def dev(self) -> ykman.base.YkmanDevice:
        return self.s._wrapped

    @functools.cached_property
    def sc(self) -> yubikit.core.smartcard.SmartCardConnection:
        sc = self.s.smart_card()
        self.context_managers.append(sc)
        return sc

    @functools.cached_property
    def piv(self) -> yubikit.piv.PivSession:
        return yubikit.piv.PivSession(self.sc)

    @functools.cached_property
    def pivman_data(self):
        return ykman.piv.get_pivman_data(self.piv)

    @functools.cached_property
    def piv_pass_suffix(self):
        return Path("piv")

    @functools.cached_property
    def piv_pass_prefix(self):
        return self.pass_prefix / self.piv_pass_suffix

    @functools.cached_property
    def piv_info(self) -> dict:
        uncategorized = []

        info = {"": uncategorized}
        for entry in ykman.piv.get_piv_info(self.piv):
            if isinstance(entry, dict):
                info.update(entry)
            else:
                uncategorized.append(entry)
        self.log = self.log.bind(piv_version=str(info["PIV version"]))
        return info

    @functools.cached_property
    def piv_management_key(self):
        return self.populate_secret(
            f"{self.piv_pass_suffix}/management-key",
            gen_cfg=dict(
                type="factory",
                factory=functools.partial(
                    ykman.piv.generate_random_management_key,
                    PIV_MANAGEMENT_KEY_TYPE,
                ),
            ),
        )

    @functools.cached_property
    def piv_pin(self):
        return self.populate_secret(
            f"{self.piv_pass_suffix}/pin", gen_cfg=dict(len=6)
        ).decode()

    @functools.cached_property
    def piv_puk(self):
        return self.populate_secret(
            f"{self.piv_pass_suffix}/puk", gen_cfg=dict(len=8)
        ).decode()

    @functools.cached_property
    def gpg_pass_suffix(self):
        return Path("gpg")

    @functools.cached_property
    def gpg_pass_prefix(self):
        return self.pass_prefix / self.gpg_pass_suffix

    @functools.cached_property
    def gpg_pin(self):
        return self.populate_secret(
            f"{self.gpg_pass_suffix}/pin", gen_cfg=dict(len=6)
        ).decode()

    @functools.cached_property
    def gpg_admin_pin(self):
        return self.populate_secret(
            f"{self.gpg_pass_suffix}/admin-pin", gen_cfg=dict(len=8)
        ).decode()

    @functools.cached_property
    def gpg_reset_code(self):
        return self.populate_secret(
            f"{self.gpg_pass_suffix}/reset-code", gen_cfg=dict(len=8)
        ).decode()

    def populate_secret(
        self, key: str, regenerate=False, default: bytes = None, gen_cfg: dict = None
    ) -> bytes:
        defaults = {}
        gen_cfgs = {}
        if default is not None:
            defaults[key] = default
        if gen_cfg is not None:
            gen_cfgs[key] = gen_cfg
        return self.populate_secrets(
            key,
            regenerate=regenerate,
            defaults=defaults,
            gen_cfgs=gen_cfgs,
        )[key]

    def populate_secrets(
        self,
        *keys: str,
        regenerate=False,
        defaults: dict[str, bytes],
        gen_cfgs: dict = None,
    ):
        if gen_cfgs is None:
            gen_cfgs = {}
        keys = tuple(map(str, keys))
        defaults = {k: v for k in keys if (v := defaults.get(k)) is not None}
        data: dict[str, bytes] = dict(defaults)
        paths = self.storage.iter(self.pass_prefix, keys=keys)

        if regenerate:
            self.log.warning(f"resetting {self.pass_prefix}")
            for path in paths:
                del self.storage[path]
            paths = []

        loaded_data = {}
        for path in paths:
            value = self.storage.get(path)
            if not value:
                continue
            loaded_data[str(path)] = data[str(path)] = value

        # store defaults in password-store
        for key, value in defaults.items():
            if loaded_data.get(key, ""):
                continue

            self.log.info(
                f"Inserted default {self.pass_prefix / key} into password-store."
            )
            self.storage[self.pass_prefix / key] = value

        for key in keys:
            pin_cfg: dict[str, typing.Any] = gen_cfgs.get(key) or {}
            key_path = self.pass_prefix / key
            str_key_path = str(key_path)
            log = self.log.bind(key=key, path=str_key_path)
            if data.get(str_key_path):
                continue
            log.info(f"generating new secret")
            length = pin_cfg.get("len")
            gen_type = pin_cfg.get("type", "storage")
            match gen_type:
                case "storage":
                    self.storage.generate(
                        key_path,
                        length=length,
                        symbols=pin_cfg.get("symbols", True),
                    )
                case "factory":
                    self.storage[key_path] = pin_cfg["factory"]()
                case _:
                    raise ValueError(f"Unknown PIN {gen_type=}")
            data[key] = self.storage[key_path]

        return data

    def ykman(self, *args: str, input: str | bytes = None, **kwargs):
        args = [
            f"--device={self.serial}",
            *map(str, args),
        ]
        # noinspection PyTypeChecker
        cli: click.Command = ykman._cli.__main__.cli
        kwargs.setdefault("standalone_mode", False)
        kwargs.setdefault("prog_name", "ykman")
        log = self.log.bind(cmd="ykman", args=shlex.join(args))
        old_stdin = sys.stdin
        if input is not None:
            sys.stdin = ChainedReader(
                click.testing.make_input_stream(input, charset="utf-8"),
                sys.stdin,
            )
        try:
            cli.main(args=args, obj={}, **kwargs)
        except SystemExit as exc:
            log.error("ykman exited with error", exc=exc)
            raise
        except Exception as exc:
            logger.error("error running ykman", args=args, exc=exc)
            raise
        finally:
            if input is not None:
                sys.stdin = old_stdin
        return

    def piv_init(self):
        management_key = ""
        # if did_reset:
        #    management_key = 3 * "0102030405060708"
        ctx = type("FakeClickContext", (object,), {})
        ctx.obj = {
            "session": self.piv,
            "pivman_data": self.pivman_data,
        }
        touch = True
        protect = True
        self.piv.authenticate(
            key_type=PIV_MANAGEMENT_KEY_TYPE,
            management_key=yubikit.piv.DEFAULT_MANAGEMENT_KEY,
        )
        # this has some logic to configure the key correctly
        ykman._cli.piv._verify_pin(
            ctx=ctx,
            session=self.piv,
            pivman=self.pivman_data,
            pin=self.piv_pin,
        )
        ykman.piv.pivman_set_mgm_key(
            session=self.piv,
            algorithm=PIV_MANAGEMENT_KEY_TYPE,
            new_key=self.piv_management_key,
            touch=touch,
            store_on_device=protect,
        )


class ChainedReader(io.TextIOBase):
    def __init__(self, *readers: typing.BinaryIO):
        self.streams = iter(readers)
        self.cur = self.advance()
        super().__init__()

    def advance(self):
        self.cur = next(self.streams, None)
        return self.cur

    def read(self, size: int = -1):
        if size == 0:
            return ""
        if self.cur is None:
            return ""
        chunks: list[str] = []
        remaining = size
        while remaining != 0 and self.cur is not None:
            chunk = self.cur.read(size)
            if isinstance(chunk, bytes):
                chunk = chunk.decode()
            chunks.append(chunk)

            remaining -= len(chunk)

            if remaining != 0:
                self.advance()

        return "".join(chunks)

    def readline(self, size=-1):
        if self.cur is None:
            return ""

        chunks = []
        total_read = 0

        while True:
            read_size = size - total_read if size >= 0 else -1
            chunk = self.cur.readline(read_size)
            if isinstance(chunk, bytes):
                chunk = chunk.decode()
            chunks.append(chunk)
            total_read += len(chunk)

            if chunk[-1:] == "\n" or (0 <= size <= total_read):
                break

            self.advance()
            if self.cur is None:
                break

        return "".join(chunks)

    def isatty(self):
        return self.cur.isatty()


class CLI:
    def __init__(self):
        self._yk: YubiKey | None = None
        self.interactive: bool = True

    def __call__(
        self,
        *,
        target: int,
        config_target: str = "",
        yes: bool = False,
    ):
        self.interactive = not yes
        config_target = str(config_target or target)
        self._yk = YubiKey(
            serial=target,
            config_target=config_target,
            storage=PasswordStore(),
        )
        return self

    def _confirm(self, prompt: str):
        if self.interactive:
            self._yk.log.warning(prompt)
            return input("[y/n]? ").strip().lower() == "y"
        self._yk.log.warning("non-interactive confirmation", prompt=prompt)
        return True

    def piv(self, *, reset=False):
        yk = self._yk
        with yk:
            logger.info("PIV info", info=json.dumps(yk.piv_info, indent=2))
            management_key_algo = yk.piv_info["Management key algorithm"]
            did_reset = False
            if reset and self._confirm("reset PIV?"):
                yk.piv.reset()
                del yk.storage[yk.piv_pass_prefix]
                yk.__dict__.pop("piv_info", None)
                did_reset = True

            if did_reset:
                yk.piv.change_pin("123456", yk.piv_pin)
                yk.piv.change_puk("12345678", yk.piv_puk)

            if did_reset or (
                management_key_algo != "TDES"
                and self._confirm(
                    f"reset PIV due to {management_key_algo=} not being TDES?"
                )
            ):
                yk.piv_init()
                yk.__dict__.pop("piv_info", None)

            # TODO: generating age-plugin-yubikey if needed


def setup_loggers():
    log_level = getattr(_logging, (os.environ.get("LOG_LEVEL") or "INFO").upper())
    structlog.stdlib.recreate_defaults(log_level=log_level)
    # `httpx` logs the auth token on INFO level by default
    httpx = _logging.getLogger("httpx")
    httpx_log_level = getattr(
        _logging, (os.environ.get("LOG_LEVEL_HTTPX") or "WARNING").upper()
    )
    httpx.setLevel(max(httpx_log_level, log_level))


@contextlib.contextmanager
def workarounds():
    """
    Workaround for Click prompt detection in pycharm
    :return:
    """
    stdin_class = ".".join(
        (sys.stdin.__class__.__module__, sys.stdin.__class__.__name__)
    )
    is_pycharm = (
        stdin_class == "_pydev_bundle.pydev_stdin.DebugConsoleStdIn"
        or "pydev" in stdin_class
    )
    old_isatty = sys.stdin.isatty
    try:
        if is_pycharm:
            sys.stdin.isatty = lambda: True
        yield
    finally:
        if is_pycharm:
            sys.stdin.isatty = old_isatty


def main():
    with workarounds():
        setup_loggers()
        fire.Fire(CLI(), name=PROGRAM)


if __name__ == "__main__":
    main()
