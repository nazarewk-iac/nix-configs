#!/usr/bin/env python3
import argparse
import functools
import itertools
import json
import logging
import os
import re
import shlex
import subprocess
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

GIT_DATE = "1970-01-01 00:00:01.000000000 +0000"


def deepmerge(a: dict, b: dict):
    out = defaultdict(dict)
    for key, value in itertools.chain(a.items(), b.items()):
        if isinstance(value, dict):
            out[key] = deepmerge(out[key], value)
        else:
            out[key] = value
    return out


def process_patch(path: Path, patch: dict):
    new = path.with_name(f"{path.name}.new")
    url = patch.get("url", None)
    if url is None:
        if "gh-compare" in patch:
            url = "https://github.com/{repo}/compare/{base}...{ref}~{skip}.patch?full_index=1".format(
                **patch["gh-compare"]
            )
    if url is not None:
        with new.open("wb") as fp:
            run(
                f"retrieve patch file: {url}",
                [
                    "curl",
                    "--silent",
                    "--fail",
                    "-L",
                    url,
                ],
                stdout=fp,
                check=True,
            )
        if path.exists():
            logging.warning(f"updating patch: {path}")
        else:
            logging.warning(f"adding patch: {path}")
        new.rename(path)
        return

    raise NotImplementedError()


def manage_block(*, path: Path, start: re.Pattern, end: re.Pattern, block: str):
    new_path = path.with_name(f"{path.name}.new")
    with path.open("rt") as old_fp, new_path.open("wt") as new_fp:
        writing = True
        for line in old_fp:
            if end.search(line) is not None:
                new_fp.write(block)
                writing = True
            if writing:
                new_fp.write(line)
            if start.search(line) is not None:
                writing = False
    new_path.rename(path)


def patches_fetch(config: dict, patches_dir: Path, update=True):
    patches_by_repo: dict[str, dict[str, Path]] = defaultdict(dict)
    defaults = config["default"]
    for base, patches in sorted(config["patch"].items()):
        for idx, (patch_name, entry) in enumerate(sorted(patches.items())):
            out = patches_dir / f"{base}/{patch_name}.patch"
            out.parent.mkdir(exist_ok=True)
            defaulted = deepmerge(defaults["patch"], entry)
            try:
                if update or not out.exists():
                    process_patch(out, defaulted)
            except Exception:
                logging.exception(
                    f"Failed to process {base}.{patch_name} = {json.dumps(entry)}"
                )
                continue
        patches_by_repo[base][patch_name] = out

    present_patches = set(
        itertools.chain(
            patches_dir.glob("*.patch"),
            (
                p
                for pd in patches_dir.iterdir()
                if pd.is_dir()
                for p in pd.glob("*.patch")
            ),
        )
    )
    configured_patches = set(
        itertools.chain(
            *(repo.values() for repo in patches_by_repo.values()),
        )
    )
    for file in present_patches - configured_patches:
        logging.warning(f"removing patch: {file}")
        file.unlink(missing_ok=True)
    return patches_by_repo


@functools.lru_cache()
def get_flake_lock(path: Path):
    with path.open("rb") as fp:
        return json.load(fp)


@functools.lru_cache()
def get_input_lock(*names: str, lock: Path):
    lock = get_flake_lock(lock)
    root_key = lock["root"]
    cur_key = lock["root"]
    cur = lock["nodes"][cur_key]

    names = list(reversed(names))
    while names:
        name = names.pop()
        cur_key = cur["inputs"][name]
        if isinstance(cur_key, list):
            names.extend(reversed(cur_key))
            cur_key = root_key
        cur = lock["nodes"][cur_key]

    return cur


def get_input_rev_locked(*names: str, lock: Path) -> str:
    cfg = get_input_lock(lock=lock, *names)
    return cfg["locked"]["rev"]


def get_input_ref(*names: str, lock: Path) -> str | None:
    cfg = get_input_lock(lock=lock, *names)
    return cfg["original"].get("ref")


def get_input_remote(*names: str, lock: Path):
    cfg = get_input_lock(lock=lock, *names)
    locked = cfg["locked"]
    repo_type = locked["type"]

    match repo_type:
        case "github":
            return "https://github.com/{owner}/{repo}".format(**locked)
        case _:
            raise NotImplementedError(f"unsupported type {repo_type}")


@functools.cache
def submodules_initialized(repo_root: Path):
    subprocess.run(
        ["git", "submodule", "update", "--init", "--recursive"],
        cwd=repo_root,
        check=True,
    )


def run(what, cmd, **kwargs):
    kwargs.setdefault("check", True)
    args = list(map(str, cmd))
    logging.info(f"{what}: {shlex.join(args)}")
    return subprocess.run(
        args,
        **kwargs,
    )


def patches_apply(
    config: dict,
    patches_dir: Path,
    lock: Path,
):
    defaults = config["default"]["repo"]
    repo_root = lock.parent
    for base in config.get("patch", {}).keys():
        base_path = patches_dir / base
        cfg = config.get("repo", {}).get("base", {})
        base_input = cfg.get("input") or defaults["input"].format(name=base)
        upstream_input = cfg.get("upstream_input") or defaults["upstream_input"].format(
            name=base
        )

        subrepo_path = base_path / "repo"
        repo_rel = subrepo_path.relative_to(repo_root)
        base_remote = get_input_remote(base_input, lock=lock)
        upstream_remote = get_input_remote(upstream_input, lock=lock)
        upstream_rev = get_input_rev_locked(upstream_input, lock=lock)

        if not subrepo_path.exists():
            # TODO: discover existing checkouts and reuse the git dir?
            run(
                f"{repo_rel}: checking out {base_remote}",
                ["git", "clone", base_remote, repo_rel],
                cwd=repo_root,
            )

        remotes = set(
            subprocess.check_output(
                ["git", "remote"],
                cwd=subrepo_path,
                encoding="utf8",
            ).split()
        )
        if "upstream" not in remotes:
            run(
                f"{repo_rel}: adding upstream {upstream_remote}",
                ["git", "remote", "add", "upstream", upstream_remote],
                cwd=subrepo_path,
            )
        else:
            run(
                f"{repo_rel}: setting upstream to {upstream_remote}",
                ["git", "remote", "set-url", "upstream", upstream_remote],
                cwd=subrepo_path,
            )
        run(
            f"{repo_rel}: fetching upstream {upstream_rev}",
            ["git", "fetch", "upstream", upstream_rev],
            cwd=subrepo_path,
        )
        run(
            f"{repo_rel}: resetting to {upstream_rev}",
            ["git", "reset", "--hard", upstream_rev],
            cwd=subrepo_path,
            check=True,
        )

        for patchfile in sorted(base_path.glob("*.patch")):
            run(
                f"{repo_rel}: applying patch {patchfile}",
                [
                    "git",
                    "am",
                    "--no-gpg-sign",
                    "--no-signoff",
                    "--committer-date-is-author-date",
                    patchfile,
                ],
                env={
                    **os.environ,
                    # "GIT_AUTHOR_DATE": GIT_DATE,
                    # "GIT_COMMITTER_DATE": GIT_DATE,
                },
                cwd=subrepo_path,
            )

        base_branch = get_input_ref(base_input, lock=lock)
        base_branch = base_branch or subprocess.check_output(
            ["git", "branch", "--show-current"],
            cwd=subrepo_path,
            encoding="utf8",
        )
        run(
            f"{repo_rel}: pushing changes to origin/{base_branch}",
            ["git", "push", "--force", "origin", base_branch],
            cwd=subrepo_path,
        )
        run(
            f"updating flake input {base_input}",
            ["nix", "flake", "update", base_input],
            cwd=repo_root,
        )


def parse_args(argv):
    argp = argparse.ArgumentParser(
        description="patch nix flake inputs semi-automatically."
    )
    argp.add_argument(
        "--flake",
        "-f",
        default=".",
        type=str,
        help="flake reference",
    )
    argp.add_argument(
        "--update",
        dest="update_patches",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="retrieves new set of patches",
    )
    argp.add_argument(
        "--apply",
        dest="apply_to_bases",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="apply set of patches",
    )
    args = argp.parse_args(argv[1:])
    return args


def main(argv):
    args = parse_args(argv)
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))

    flake = Path(args.flake).absolute()
    patches_dir = flake / ".flake.patches"
    flake_lock = flake / "flake.lock"
    config = tomllib.loads((patches_dir / "config.toml").read_text())

    try:
        patches_fetch(config, patches_dir, update=args.update_patches)
        if args.apply_to_bases:
            patches_apply(config=config, patches_dir=patches_dir, lock=flake_lock)
    except subprocess.CalledProcessError as exc:
        logging.error(f"command failed with {exc.returncode}: {shlex.join(exc.cmd)}")
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv)
