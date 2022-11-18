import dataclasses
import itertools
import logging
import os
import re
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


def get_default_store_dir():
    return Path(os.environ.get("PASSWORD_STORE_DIR") or Path.home() / ".password-store")


terminal_escape_code = re.compile(r"\x1b[^m]*m")


@dataclasses.dataclass
class PasswordStore:
    binary: Path
    store_dir: Path = dataclasses.field(default_factory=get_default_store_dir)

    def cmd(self, args, **kwargs):
        kwargs.setdefault("check", True)
        return subprocess.run(
            list(map(str, itertools.chain([self.binary], args))),
            stdout=subprocess.PIPE,
            env={
                **os.environ,
                **kwargs.get('env', {}),
                'PASSWORD_STORE_DIR': str(self.store_dir),
            },
            **kwargs,
        )

    def __iter__(self):
        yield from self.iter(Path("/"))

    def __getitem__(self, path: Path) -> bytes:
        # pass adds a newline at the end
        return self.cmd(["show", path]).stdout[:-1]

    def __setitem__(self, path: Path, value: bytes):
        self.cmd(
            ["insert", "--force", path],
            input=(b"%s\n" % value) * 2,
        )

    def __delitem__(self, path: Path):
        self.delete(path, recursive=True)

    def delete(self, path: Path, recursive=False):
        args = ["rm", "--force"]
        if recursive:
            args.append("--recursive")
        self.cmd([*args, path], check=True)

    def iter(self, path: Path, relative=False):
        path = self.store_dir / path
        for entry in path.rglob("*.gpg"):
            entry = entry.with_suffix("")
            entry = entry.relative_to(self.store_dir)
            if relative:
                entry = entry.relative_to(path)
            yield entry

    def generate(self, path: Path, length=6, symbols=True):
        # see https://git.zx2c4.com/password-store/tree/src/password-store.sh#n561
        args = ["generate"]
        if not symbols:
            args.append("--no-symbols")
        proc = self.cmd(
            [*args, path, str(length)],
            stdout=subprocess.PIPE,
        )
        value = proc.stdout.splitlines(False)[-1].decode()
        return terminal_escape_code.sub("", value)
