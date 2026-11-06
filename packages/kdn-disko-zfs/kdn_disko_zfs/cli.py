"""kdn-disko-zfs — plan/apply a host's disko-declared ZFS datasets.

See the README for the why. This module is the CLI; the pure logic lives in
`core.py` and is unit-tested in `tests/`.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from . import core

# Fast-fail, non-interactive ssh: an unreachable host must not hang the tool.
SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]


def say(*parts: object) -> None:
    print(">", *parts, file=sys.stderr)


def run(cmd: list[str], *, check: bool = True, capture: bool = False, sudo: bool = False) -> str:
    full = ["sudo", *cmd] if sudo else cmd
    say(" ".join(full))
    if capture:
        result = subprocess.run(full, text=True, capture_output=True)
        if check and result.returncode != 0:
            sys.stderr.write(result.stderr)
            raise SystemExit(f"command failed ({result.returncode}): {' '.join(full)}")
        return result.stdout
    subprocess.run(full, check=check)
    return ""


def local_identifiers() -> set[str]:
    node = os.uname().nodename
    return {node, node.split(".")[0]}


def target_system(repo: str, host: str) -> str:
    expr = (
        f'let f = builtins.getFlake "{repo}"; '
        f'c = f.nixosConfigurations."{host}".config; in '
        "c.system.build.toplevel.system"
    )
    return run(["nix", "eval", "--impure", "--raw", "--expr", expr], capture=True).strip()


def resolve_disko_zfs(target_sys: str, repo: str) -> str:
    local_sys = run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], capture=True
    ).strip()
    if target_sys == local_sys:
        found = shutil.which("disko-zfs")
        if found:
            return str(Path(found).resolve())
    say(f"building disko-zfs for {target_sys} (repo flake input)")
    expr = f'let f = builtins.getFlake "{repo}"; in f.inputs.disko-zfs.packages."{target_sys}".default'
    out = run(["nix", "build", "--impure", "--no-link", "--print-out-paths", "--expr", expr], capture=True)
    return str(Path(out.strip().splitlines()[-1]) / "bin" / "disko-zfs")


class Context:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.host = args.host or os.uname().nodename.split(".")[0]
        # The flake attr (`-H`) and the ssh target can differ; `--ssh-host` overrides.
        self.ssh_host = getattr(args, "ssh_host", None) or self.host
        self.repo = args.repo or self._git_root()
        if not (Path(self.repo) / "flake.nix").is_file():
            sys.exit(f"error: no flake.nix in {self.repo} (pass -r PATH)")
        self.tmp = tempfile.mkdtemp(prefix="kdn-disko-zfs.")
        self.spec_path = Path(args.spec_file) if args.spec_file else Path(self.tmp) / "spec.json"
        self.remote_spec = f"/tmp/kdn-disko-zfs-{self.host}.json"
        self._binary: str | None = None
        self._target_sys: str | None = None

    @staticmethod
    def _git_root() -> str:
        try:
            out = subprocess.run(
                ["git", "-C", str(Path.cwd()), "rev-parse", "--show-toplevel"],
                check=True, text=True, capture_output=True,
            ).stdout.strip()
            return out or str(Path.cwd())
        except subprocess.CalledProcessError:
            return str(Path.cwd())

    @property
    def is_local(self) -> bool:
        return self.host in ("localhost", *local_identifiers())

    def binary(self) -> str:
        if self._binary is None:
            if self.args.disko_zfs:
                self._binary = str(Path(self.args.disko_zfs).resolve())
            else:
                self._target_sys = target_system(self.repo, self.host)
                say(f"target host '{self.host}' system: {self._target_sys}")
                self._binary = resolve_disko_zfs(self._target_sys, self.repo)
            say(f"disko-zfs: {self._binary}")
        return self._binary

    # -- spec ---------------------------------------------------------------
    def gen_spec(self) -> dict:
        say(f"nix eval: derive disko ZFS datasets for '{self.host}' from {self.repo}")
        raw = run(
            ["nix", "eval", "--impure", "--json", "--expr", core.gen_spec_expr(self.repo, self.host)],
            capture=True,
        )
        spec = core.parse_spec(raw)
        self.spec_path.parent.mkdir(parents=True, exist_ok=True)
        self.spec_path.write_text(json.dumps(spec, indent=2) + "\n")
        say(f"spec: {self.spec_path} ({len(core.dataset_names(spec))} datasets)")
        return spec

    def write_spec(self, spec: dict) -> None:
        self.spec_path.write_text(json.dumps(spec, indent=2) + "\n")

    # -- host calls ---------------------------------------------------------
    def _remote_bin(self) -> str:
        say(f"nix copy --to ssh-ng://{self.ssh_host} (disko-zfs)")
        rc = subprocess.run(
            ["nix", "copy", "--no-check-sigs", "--to", f"ssh-ng://{self.ssh_host}", self.binary()],
            check=False,
        ).returncode
        if rc != 0:
            sys.exit(f"error: failed to copy disko-zfs to {self.ssh_host} (nix copy rc={rc})")
        return self.binary()

    def host_show(self) -> dict:
        if self.is_local:
            out = run([self.binary(), "show"], capture=True, sudo=True)
        else:
            binpath = self._remote_bin()
            say(f"ssh {self.ssh_host} sudo {binpath} show")
            out = subprocess.run(
                ["ssh", *SSH_OPTS, self.ssh_host, "sudo", binpath, "show"],
                check=True, text=True, capture_output=True,
            ).stdout
        return json.loads(out)

    def _push_spec(self) -> str:
        if self.is_local:
            return str(self.spec_path)
        say(f"scp {self.spec_path} -> {self.ssh_host}:{self.remote_spec}")
        subprocess.run(["scp", *SSH_OPTS, "-q", str(self.spec_path), f"{self.ssh_host}:{self.remote_spec}"], check=True)
        return self.remote_spec

    def host_disko(self, *args: str) -> str:
        spec_on_host = self._push_spec()
        if self.is_local:
            return run([self.binary(), *args, "--spec", spec_on_host], capture=True, sudo=True)
        binpath = self.binary()
        say(f"ssh {self.ssh_host} sudo {binpath} {' '.join(args)} --spec {spec_on_host}")
        return subprocess.run(
            ["ssh", *SSH_OPTS, self.ssh_host, "sudo", binpath, *args, "--spec", spec_on_host],
            check=True, text=True, capture_output=True,
        ).stdout


def emit(text: str) -> None:
    sys.stdout.write(text if text.endswith("\n") else text + "\n")


def cmd_spec(ctx: Context) -> None:
    spec = ctx.gen_spec()
    emit(json.dumps(spec, indent=2))


def cmd_show(ctx: Context) -> None:
    emit(json.dumps(ctx.host_show(), indent=2))


def cmd_plan(ctx: Context, apply: bool = False) -> None:
    spec = ctx.gen_spec()
    if ctx.args.dry_run and not ctx.is_local:
        say(f"DRY RUN (host '{ctx.host}' not contacted). Commands the spec implies:")
        emit("\n".join(core.dry_run_commands(spec)))
        return
    ctx.binary()
    if not ctx.args.dry_run:
        live = ctx.host_show()
        ignored = core.compute_ignored(core.dataset_names(spec), core.dataset_names(live))
        if ignored:
            say(f"auto-ignoring {len(ignored)} undeclared live datasets")
            ctx.write_spec(core.merge_ignores(spec, ignored))
    say("disko-zfs plan")
    plan_text = ctx.host_disko("plan")
    emit(plan_text)
    if apply:
        if core.has_destructive(plan_text) and not ctx.args.force:
            sys.exit("REFUSING: plan has destructive commands (use --force)")
        say("disko-zfs apply")
        emit(ctx.host_disko("apply"))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="kdn-disko-zfs",
        description="Plan/apply a host's disko-declared ZFS datasets via disko-zfs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "spec is generated from the host's NixOS disko config, so it is always\n"
            "in step with hosts/<host>/disko.nix. plan/apply auto-ignore every live\n"
            "dataset the config does not declare, and apply refuses destructive plans\n"
            "unless --force."
        ),
    )
    p.add_argument("command", nargs="?", default="plan", choices=["spec", "show", "plan", "apply"])
    p.add_argument("-H", "--host", help="target host / flake attr (default: this machine)")
    p.add_argument("--ssh-host", dest="ssh_host", help="ssh target if it differs from --host")
    p.add_argument("-r", "--repo", help="repo checkout with the flake (default: git root)")
    p.add_argument("-s", "--spec-file", help="spec path to write/read (default: temp)")
    p.add_argument("--dry-run", action="store_true", help="do not contact the host; print implied creates")
    p.add_argument("--force", action="store_true", help="apply even if destructive commands are present")
    p.add_argument("--disko-zfs", dest="disko_zfs", help="disko-zfs binary to use")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    ctx = Context(args)
    try:
        if args.command == "spec":
            cmd_spec(ctx)
        elif args.command == "show":
            cmd_show(ctx)
        elif args.command == "plan":
            cmd_plan(ctx, apply=False)
        elif args.command == "apply":
            cmd_plan(ctx, apply=True)
    finally:
        shutil.rmtree(ctx.tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
