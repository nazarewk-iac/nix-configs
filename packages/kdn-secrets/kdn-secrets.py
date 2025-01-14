import dataclasses
import functools
import hashlib
import json
import logging as _logging
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import fire
import structlog
import xdg_base_dirs

APP_NAME = "kdn-secrets"
logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@dataclasses.dataclass(order=True, slots=True, unsafe_hash=True)
class PathEvent:
    absolute: Path = dataclasses.field(hash=True, compare=True)
    metadata: dict = dataclasses.field(hash=False, compare=False)
    filetype: str = dataclasses.field(default="other", hash=True, compare=True)


@dataclasses.dataclass()
class Secrets:
    APP_SUBPATH = "kdn/secrets"
    extra_config_dirs: tuple[Path] = ()

    @functools.cached_property
    def config_dirs(self):
        xdg_dirs = (
            *self.extra_config_dirs,
            xdg_base_dirs.xdg_config_home(),
            *xdg_base_dirs.xdg_config_dirs(),
        )
        return [entry / self.APP_SUBPATH for entry in xdg_dirs]

    @functools.cached_property
    def config_dirs_set(self):
        return set(self.config_dirs)

    @functools.cached_property
    def runtime_dir(self):
        return xdg_base_dirs.xdg_runtime_dir() / self.APP_SUBPATH

    def get_workdir(self, subdir: Path):
        assert not subdir.is_absolute()
        return self.output_path.with_suffix(".d") / subdir

    @functools.cached_property
    def output_path(self):
        return self.runtime_dir

    def watch(self):
        cmd = [
            "watchexec",
            "--emit-events-to=json-stdio",
            "--debounce=333ms",
            "--filter=*.sops.*",
            *(f"--watch={d}" for d in self.config_dirs),
        ]

        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            bufsize=1,
            universal_newlines=True,
        ) as process:
            for line in process.stdout:
                self.process_line(line)

            if process.returncode != 0:
                raise subprocess.CalledProcessError(process.returncode, cmd)

    def process_line(self, line: bytes):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            logger.exception("failed to parse output line", line=line)
            return
        metadata = data.get("metadata") or {}
        for tag in data.get("tags", []):
            if tag["kind"] != "path":
                continue
            kwargs = dict(
                metadata=metadata,
                absolute=Path(tag["absolute"]),
            )
            if ft := tag.get("filetype"):
                kwargs["filetype"] = ft
            event = PathEvent(**kwargs)
            log = logger.bind(evt=event)
            log.debug("event received")
            self.process_path(event.absolute, log=log)

    @staticmethod
    def calculate_checksum(path: Path):
        try:
            return hashlib.sha256(path.read_bytes()).hexdigest()
        except FileNotFoundError:
            return ""

    def process_all(self):
        processed = set()
        for config_dir in self.config_dirs:
            for file in config_dir.glob("*/*.sops.*"):
                base = config_dir.name
                filename = file.stem.removesuffix(".sops")
                relpath = Path(base) / filename
                if relpath in processed:
                    continue
                processed.add(relpath)
                self.process_path(file.absolute())

    def find_highest_priority(self, relpath: Path):
        for config_dir in self.config_dirs:
            for new_file in sorted(config_dir.glob(f"{relpath}.sops.*")):
                return new_file

    def process_path(self, file: Path, *, log=logger):
        try:
            config_dir = file.parent.parent
            filename = file.stem.removesuffix(".sops")
            base = config_dir.name
            relpath = Path(base) / filename
            log = log.bind(
                cofig_dir=str(config_dir),
                base=config_dir.name,
                filename=filename,
            )

            err = False

            if config_dir not in self.config_dirs_set:
                log.error("file is not from config directory")
                err = True

            if file.suffixes[-2] != ".sops":
                log.error("file must match `<name>.sops.<suffix>` pattern")
                err = True

            if err:
                return err

            # find highest-priority file
            new_file = self.find_highest_priority(relpath)
            if new_file != file:
                log.info(
                    "not a highest priority file, ignoring it",
                    higher_priority=new_file,
                )
                return err

            new_checksum = self.calculate_checksum(file)
            if not new_checksum:
                log.info("file removed")
                return err

            cwd = self.get_workdir(relpath)
            target_file = cwd / f"{new_checksum}.json"

            if target_file.exists():
                log.debug("file already rendered", checksum=new_checksum)
            else:
                cwd.mkdir(mode=0o750, parents=True, exist_ok=True)
                new = target_file.with_name(f"{target_file.name}.new")

                cmd = [
                    "sops",
                    "decrypt",
                    "--output-type=json",
                    f"--output={new}",
                    file,
                ]
                try:
                    subprocess.check_call(cmd)
                except subprocess.CalledProcessError:
                    log.error("sops decrypt failed", cmd=shlex.join(cmd))
                    err = True
                new.write_text(
                    json.dumps(
                        json.loads(new.read_bytes()),
                        indent=0,
                        separators=(",", ":"),
                    )
                )
                shutil.move(new, target_file)

            latest = self.output_path / f"{relpath}.json"
            log = log.bind(latest=latest)
            latest.parent.mkdir(mode=0o750, parents=True, exist_ok=True)

            if latest.exists() and not latest.is_symlink():
                log.warning("latest exists and is not a symlink")
                shutil.rmtree(latest)
            if not latest.is_symlink() or latest.resolve() != target_file:
                log.warning("latest symlink updated")
                latest.symlink_to(target_file)

            return err
        except Exception:
            log.exception("failed to process file")
            return True


@dataclasses.dataclass()
class Program:
    def __init__(self):
        self.s = Secrets()

    # def __call__(self, *args, **kwargs):
    #    logger.debug("__call__()", args=args, kwargs=kwargs)

    def watch(self):
        self.s.watch()

    def process_all(self):
        self.s.process_all()


def main():
    structlog.stdlib.recreate_defaults(
        log_level=getattr(_logging, os.environ.get("LOG_LEVEL") or "DEBUG")
    )
    fire.Fire(Program)


if __name__ == "__main__":
    main()
