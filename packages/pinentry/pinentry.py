#!/run/current-system/sw/bin/python3
from __future__ import annotations

import dataclasses
import functools
import json
import logging
import os
import queue
import re
import shlex
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Callable, Any, TextIO
from urllib.parse import unquote, quote

program_name = "pinentry-kdn"
logger_name = program_name.replace("-", "_")
logger = logging.getLogger(logger_name)


class Exit(Exception):
    pass


@dataclasses.dataclass()
class PinentryMessage:
    line: str
    write: Callable[[str], Any]
    escaped: bool = True

    def __post_init__(self):
        self.line = self.line.rstrip("\n")

    @functools.cached_property
    def sep_idx(self):
        try:
            return self.line.index(" ")
        except ValueError:
            return len(self.line)

    @functools.cached_property
    def command(self):
        return self.line[: self.sep_idx]

    @functools.cached_property
    def data_input(self):
        return self.line[self.sep_idx + 1 :]

    @functools.cached_property
    def data_escaped(self):
        if self.escaped:
            return self.data_input
        return self.escape(self.data_input)

    @functools.cached_property
    def data(self):
        if self.escaped:
            return self.unescape(self.data_input)
        return self.data_input

    @functools.cached_property
    def masked_line(self):
        pieces = [
            self.command,
            "*" * len(self.data),
        ]
        return " ".join(filter(bool, pieces))

    def forward(self):
        logger.debug(f"{self}")
        self.write(" ".join(filter(bool, [self.command, self.data_escaped])) + "\n")

    def __str__(self):
        return self.line

    @classmethod
    def escape(cls, txt: str):
        txt = txt.replace("%", "%25")
        txt = txt.replace("\n", "%0A")
        return txt

    @classmethod
    def unescape(cls, txt: str):
        txt = txt.replace("%25", "%")
        txt = txt.replace("%0A", "\n")
        return txt


@dataclasses.dataclass()
class PinentryRequest(PinentryMessage):
    def is_sensitive(self):
        return self.command == "GETPIN"

    def __str__(self):
        return f"C: {self.line}"


@dataclasses.dataclass()
class PinentryResponse(PinentryMessage):
    request: PinentryRequest = None

    def __str__(self):
        if self.request and self.request.is_sensitive():
            line = self.masked_line
        else:
            line = self.line
        return f"S: {line}"

    def is_ok(self):
        return self.command == "OK"

    def is_error(self):
        return self.command == "ERR"

    def is_last(self):
        return self.is_ok() or self.is_error()


@dataclasses.dataclass
class PinentryConfigPattern:
    pattern: str
    inverse: bool = False
    multiline: bool = False
    verbose: bool = False
    ignorecase: bool = False

    @functools.cached_property
    def re(self):
        flags = re.RegexFlag.NOFLAG
        if self.multiline:
            flags |= re.RegexFlag.MULTILINE
        if self.verbose:
            flags |= re.RegexFlag.VERBOSE
        if self.ignorecase:
            flags |= re.RegexFlag.IGNORECASE
        return re.compile(self.pattern, flags)

    def matches(self, txt: str):
        match = bool(self.re.search(txt))
        if self.inverse:
            match = not match
        return match


@dataclasses.dataclass
class PinentryConfigExec:
    value: str | None = None
    program: list[str] | None = None
    option_patterns: dict[str, list[PinentryConfigPattern]] = dataclasses.field(
        default_factory=dict
    )
    set_patterns: dict[str, list[PinentryConfigPattern]] = dataclasses.field(
        default_factory=dict
    )

    def __post_init__(self):
        assert self.value or self.program
        assert self.option_patterns or self.set_patterns
        self.option_patterns = {
            key: [
                PinentryConfigPattern(**pattern)
                if isinstance(pattern, dict)
                else pattern
                for pattern in patterns
            ]
            for key, patterns in self.option_patterns.items()
        }
        self.set_patterns = {
            key: [
                PinentryConfigPattern(**pattern)
                if isinstance(pattern, dict)
                else pattern
                for pattern in patterns
            ]
            for key, patterns in self.set_patterns.items()
        }

    def matches(self, pinentry: Pinentry):
        return all(
            pattern.matches(pinentry.options.get(name, ""))
            for name, patterns in self.option_patterns.items()
            for pattern in patterns
        ) and all(
            pattern.matches(pinentry.sets.get(name, ""))
            for name, patterns in self.set_patterns.items()
            for pattern in patterns
        )

    @functools.cached_property
    def output(self):
        if self.value:
            return self.value
        return subprocess.check_output(self.program, encoding="utf8")


@dataclasses.dataclass
class PinentryConfig:
    gui_flavors: tuple[str, ...] = ("qt", "gtk-2", "gnome3")
    tty_flavors: tuple[str, ...] = ("curses", "tty")
    program: str = ""
    exec: dict[str, PinentryConfigExec] = dataclasses.field(default_factory=dict)

    def __post_init__(self):
        self.merge({})

    @functools.cached_property
    def flavors(self):
        flavors = self.tty_flavors
        if os.environ.get("XDG_CURRENT_DESKTOP"):
            flavors = (*self.gui_flavors, *flavors)
        return flavors

    @functools.cached_property
    def candidates(self):
        ret = tuple(map("pinentry-{}".format, self.flavors))
        if self.program:
            ret = (self.program, *ret)
        return ret

    @functools.cached_property
    def binary(self):
        binary = None
        for candidate in self.candidates:
            if binary := shutil.which(candidate):
                binary = Path(binary)
                break
        if binary and not binary.is_absolute():
            binary = Path(shutil.which(binary))
        if not binary:
            logger.error("pinentry not found, tried: " + " ".join(self.candidates))
            sys.exit(1)
        return Path(binary)

    @classmethod
    def paths(cls, path: str = ""):
        r = [
            path,
            os.environ.get("PINENTRY_CONFIG"),
        ]
        r.extend(
            Path(d) / program_name / "config.toml"
            for d in (
                os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"),
                *os.environ.get("XDG_CONFIG_DIRS", "").split(os.path.pathsep),
            )
        )

        return reversed(
            [
                path
                for candidate in r
                if candidate and (path := Path(candidate)).exists()
            ]
        )

    @classmethod
    def get(cls, path: str):
        self = cls()
        for candidate in cls.paths(path):
            logger.info(f"found config at {candidate}")
            with candidate.open("rb") as fp:
                data = tomllib.load(fp)
            self.merge(data)
        return self

    def merge(self, data: dict):
        for key, value in data.items():
            match key:
                case "exec":
                    value = {
                        key: PinentryConfigExec(**value) for key, value in value.items()
                    }
                    setattr(self, key, value)
                case _:
                    setattr(self, key, value)


@dataclasses.dataclass
class Pinentry:
    args: tuple[str]
    input: TextIO
    output: TextIO
    request: PinentryRequest | None = None
    process: subprocess.Popen = dataclasses.field(init=False)
    options: dict[str, str] = dataclasses.field(default_factory=dict)
    sets: dict[str, str] = dataclasses.field(default_factory=dict)
    extra: queue.Queue[str] = dataclasses.field(default_factory=queue.Queue)
    config_path: str = ""

    @functools.cached_property
    def config(self):
        return PinentryConfig.get(self.config_path)

    def __post_init__(self):
        logger = logging.getLogger(f"{logger_name}.__post_init__")
        args = [self.config.binary, *self.args]
        logger.info(f"executing: {shlex.join(map(str, args))}")
        self.process = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            bufsize=0,
            universal_newlines=True,
        )

    def __iter__(self):
        logger = logging.getLogger(f"{logger_name}.__iter__")
        with self.process:
            while True:
                try:
                    line = self.extra.get_nowait()
                except queue.Empty:
                    try:
                        line = self.input.readline().strip()
                    except ValueError as exc:
                        logger.info(f"exception {exc}, exiting...")
                        return
                self.request = request = PinentryRequest(
                    line=line,
                    write=self._request_write,
                )
                logger.info(f"{request}")
                yield request

    def receive(self):
        logger = logging.getLogger(f"{logger_name}.receive")
        while True:
            try:
                line = self.process.stdout.readline().strip()
            except ValueError as exc:
                logger.info(f"exception {exc}, exiting...")
                return
            response = PinentryResponse(
                line=line,
                write=self._response_write,
                request=self.request,
            )
            logger.info(f"{response}")
            yield response
            if response.is_last():
                logger.debug(f"processed {self.request}")
                self.request = None
                return

    def _request_write(self, txt: str):
        logger.debug(f"forwarding {txt=}")
        ret = self.process.stdin.write(txt)
        self.process.stdin.flush()
        return ret

    def _response_write(self, txt: str):
        if self.output.closed:
            return 0
        if self.request and self.request.is_sensitive() and txt.startswith("D "):
            log_txt = txt[:3] + "*" * (len(txt) - 5) + txt[-2:]
            logger.debug(f"outputting PIN {log_txt=}")
        else:
            logger.debug(f"outputting {txt=}")
        ret = self.output.write(txt)
        try:
            self.output.flush()
        except BrokenPipeError as exc:
            logger.error(f"{exc}")
        return ret

    def inject_request(self, line: str):
        self.extra.put_nowait(line)

    @functools.cached_property
    def prefix_handlers(self) -> dict[str, Callable[[], None]]:
        prefix = "handle_prefix_"
        return {
            name.removeprefix(prefix).upper(): getattr(self, name)
            for name in dir(self)
            if name.startswith(prefix)
        }

    def run(self):
        handle: Callable[[], None]
        for response in self.receive():
            response.forward()
        for request in self:
            handle = None
            match request.command:
                case "GETPIN" | "CONFIRM":
                    logger.debug(
                        json.dumps(
                            dict(sets=self.sets, options=self.options),
                            sort_keys=True,
                            indent=2,
                        )
                    )
                case cmd:
                    if not handle:
                        for name, handler in self.prefix_handlers.items():
                            if cmd.startswith(name):
                                logger.debug(f"matched prefix handler {name}")
                                handle = handler
                            break
            if not handle:
                handle = getattr(self, f"handle_{request.command.lower()}", None)
                if handle:
                    logger.debug(f"matched command handler {request.command}")
            if not handle:
                handle = self.handle
                if handle:
                    logger.debug(f"matched default handler")
            try:
                handle()
            except Exit:
                return

    def respond(self, *lines: str):
        for line in lines:
            PinentryResponse(
                line=line,
                escaped=False,
                request=self.request,
                write=self._response_write,
            ).forward()
        PinentryResponse(
            line="OK",
            request=self.request,
            write=self._response_write,
        ).forward()

    def forward_responses(self):
        for response in self.receive():
            response.forward()

    def discard_responses(self):
        for _ in self.receive():
            pass

    def handle_prefix_set(self):
        self.sets[self.request.command] = self.request.data

        self.request.forward()
        self.forward_responses()

    def handle_option(self):
        data = self.request.data
        try:
            idx = data.index("=")
        except ValueError:
            idx = len(data)
        key = data[:idx]
        self.options[key] = data[idx + 1 :]

        self.request.forward()
        self.forward_responses()

    def handle_bye(self):
        self.request.forward()
        self.discard_responses()
        raise Exit()

    def handle(self):
        self.request.forward()
        self.forward_responses()


class PinentryExec(Pinentry):
    def handle_getpin(self):
        for name, exec in self.config.exec.items():
            if not exec.matches(pinentry=self):
                logger.info(f"exec did not match {name=}")
                continue
            logger.info(f"exec matched {name=}")
            data = exec.output
            self.respond(f"D {PinentryMessage.escape(data)}")
            return

        self.request.forward()
        self.forward_responses()


def main(program: str, *args: str):
    is_development = program.endswith(".py")

    log_dir = Path(os.environ.get("GPGHOME") or Path.home() / ".gnupg")
    log_fmt = [
        "asctime",
        "levelname",
        "name",
        "funcName",
    ]
    log_fmt = " | ".join(map("%({})s".format, log_fmt))
    log_fmt = f"[{log_fmt}] %(message)s"
    logging.basicConfig(
        filename=log_dir / f"{program_name}.log",
        format=log_fmt,
        level=logging.getLevelName(os.environ.get("PINENTRY_LOG_LEVEL", "DEBUG")),
    )

    if is_development:
        handler = logging.StreamHandler(sys.stderr)
        handler.formatter = logging.root.handlers[0].formatter
        logging.root.addHandler(handler)
        os.environ["PATH"] = os.path.pathsep.join(
            [
                "/run/current-system/sw/bin",
                *os.environ.get("PATH", "").split(os.path.pathsep),
            ]
        )

    logger.debug(shlex.join(map(str, [program, *args])))
    logger.debug(json.dumps(dict(os.environ), sort_keys=True, indent=2))
    PinentryExec(
        args=args,
        input=sys.stdin,
        output=sys.stdout,
    ).run()


if __name__ == "__main__":
    try:
        main(*sys.argv)
    except SystemExit:
        pass
    except Exception:
        logger.exception("pinentry failed")
