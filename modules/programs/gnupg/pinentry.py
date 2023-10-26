#!/usr/bin/env python
import contextlib
import logging
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import sys

# TODO: handle some entries by itself: https://gist.github.com/Cimbali/862a430a0f28ffe07f8ae618e8b73973

log_dir = Path(os.environ.get("GPGHOME") or Path.home() / ".gnupg")
debug = True
logging.basicConfig(filename=log_dir / "pinentry.log", level=logging.DEBUG)
logging.info(f"STARTED[{os.getpid()}]: {shlex.join(sys.argv)}")

bins = {
    entry: shutil.which(entry)
    for entry in [
        "tee",
        "cat",
        "pinentry-qt",
        "pinentry-curses",
    ]
}

paths = os.environ["PATH"].split(os.path.pathsep)
logging.debug(f"searched in {paths=}")
logging.debug(f"using following binaries: {bins=}")
assert all(bins.values())

PINENTRY_USER_DATA = os.environ.get("PINENTRY_USER_DATA", "")
flavor = os.environ.get("PINENTRY_FLAVOR")

if not flavor:
    match os.environ.get("XDG_CURRENT_DESKTOP", "").strip():
        case "":
            flavor = "curses"
        case _:
            flavor = "qt"


@contextlib.contextmanager
def tee(out, tee_kwargs=None) -> subprocess.Popen:
    tee_kwargs = tee_kwargs or {}
    read_fd, write_fd = os.pipe()
    with subprocess.Popen([bins["cat"], "-n"], stdin=read_fd, stdout=out) as processor:
        logging.debug(f"started: {processor.args=}")
        with subprocess.Popen(
            [bins["tee"], f"/dev/fd/{write_fd}"], pass_fds=[write_fd], **tee_kwargs
        ) as tee:
            logging.debug(f"started: {tee.args=}")
            yield tee
        logging.debug(f"exited: {tee.args=}")
        os.close(write_fd)
    logging.debug(f"exited: {processor.args=}")


logging.info(f"{flavor=}")

match flavor:
    case "":
        sys.exit(1)
    case _:
        if not debug:
            proc = subprocess.run([bin, *sys.argv[1:]])
            sys.exit(proc.returncode)

        with (
            (log_dir / "pinentry.input.log").open("ab") as in_fp,
            (log_dir / "pinentry.output.log").open("ab") as out_fp,
        ):
            in_fp.write(f"=== {os.getpid()} ===\n".encode())
            in_fp.flush()
            out_fp.write(f"=== {os.getpid()} ===\n".encode())
            out_fp.flush()
            with (
                tee(in_fp, tee_kwargs=dict(stdout=subprocess.PIPE)) as tee_in,
                tee(out_fp, tee_kwargs=dict(stdin=subprocess.PIPE)) as tee_out,
            ):
                with subprocess.Popen(
                    [bins[f"pinentry-{flavor}"], *sys.argv[1:]],
                    # ["sed", "s/^/processed: /g"],
                    stdin=tee_in.stdout,
                    stdout=tee_out.stdin,
                ) as proc:
                    logging.debug(f"started: {proc.args=}")
                logging.debug(f"exited: {proc.args=}")
            logging.debug("exited all tees")
        sys.exit(proc.returncode)
