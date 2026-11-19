#!/usr/bin/env python3
"""Summarise certificate expiry so a shell entry can warn without decoding anything.

Decoding every certificate on every activation is wasteful and, on a slow host, noticeable. This
script does the decoding once and writes `data/certs/expiry.json`; the devenv shell only reads that
file (`--remind`), which is a single JSON load.

Modes:
  (default)   recompute the summary and write it
  --check     recompute and exit 1 when the committed file is stale (wire this into a check)
  --remind    read the committed summary and print a warning when the nearest expiry is close

The summary covers the SSH host certificates under `hosts/*/certs/*-cert.pub` and the X.509 CA
certificates under `data/ca/*.crt`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUMMARY = ROOT / "data" / "certs" / "expiry.json"

# Warn this many days before the nearest expiry, then again at the second threshold.
WARN_DAYS = 45
URGENT_DAYS = 14


def ssh_cert_not_after(path: pathlib.Path) -> dt.datetime:
    """Parse the `Valid: from … to …` line of an OpenSSH certificate."""
    out = subprocess.run(
        ["ssh-keygen", "-L", "-f", str(path)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("Valid:"):
            continue
        _, _, window = line.partition("from ")
        _, _, valid_to = window.partition(" to ")
        # `ssh-keygen -L` prints a LOCAL wall-clock time with no zone. Convert it so the summary is
        # the same on a CET workstation and in a UTC build sandbox.
        return dt.datetime.fromisoformat(valid_to.strip()).astimezone(dt.timezone.utc)
    raise SystemExit(f"{path}: no validity window in ssh-keygen output")


def x509_not_after(path: pathlib.Path) -> dt.datetime:
    out = subprocess.run(
        ["openssl", "x509", "-in", str(path), "-noout", "-enddate"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    _, _, stamp = out.partition("=")
    # `openssl x509 -enddate` prints GMT explicitly; `%Z` does not carry it into the datetime.
    return dt.datetime.strptime(stamp.strip(), "%b %d %H:%M:%S %Y %Z").replace(
        tzinfo=dt.timezone.utc
    )


def collect() -> dict:
    entries = []
    for cert in sorted(ROOT.glob("hosts/*/certs/*-cert.pub")):
        entries.append(
            {
                "path": str(cert.relative_to(ROOT)),
                "kind": "ssh-host",
                "notAfter": ssh_cert_not_after(cert).isoformat(),
            }
        )
    for cert in sorted(ROOT.glob("data/ca/*.crt")):
        entries.append(
            {
                "path": str(cert.relative_to(ROOT)),
                "kind": "ca",
                "notAfter": x509_not_after(cert).isoformat(),
            }
        )
    if not entries:
        raise SystemExit("no certificates found; run from the repository root")

    entries.sort(key=lambda entry: entry["notAfter"])
    return {
        "generated": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat(),
        "earliest": entries[0],
        "certificates": entries,
    }


def write() -> int:
    summary = collect()
    SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY.write_text(json.dumps(summary, indent=2) + "\n")
    print(
        f"wrote {SUMMARY.relative_to(ROOT)}: {len(summary['certificates'])} certificates, "
        f"earliest {summary['earliest']['notAfter']}"
    )
    return 0


def check() -> int:
    fresh = collect()
    if not SUMMARY.exists():
        print(
            f"{SUMMARY.relative_to(ROOT)} is missing; run hack/certs-expiry.py",
            file=sys.stderr,
        )
        return 1
    committed = json.loads(SUMMARY.read_text())
    if committed.get("certificates") == fresh["certificates"]:
        return 0
    print(
        f"{SUMMARY.relative_to(ROOT)} is stale; run hack/certs-expiry.py",
        file=sys.stderr,
    )
    # Say which entries differ, so a stale summary in CI is actionable without a local rerun.
    before = {
        entry["path"]: entry["notAfter"] for entry in committed.get("certificates", [])
    }
    after = {entry["path"]: entry["notAfter"] for entry in fresh["certificates"]}
    for path in sorted(set(before) | set(after)):
        if before.get(path) != after.get(path):
            print(
                f"  {path}: committed {before.get(path)}, actual {after.get(path)}",
                file=sys.stderr,
            )
    return 1


def remind() -> int:
    if not SUMMARY.exists():
        return 0
    summary = json.loads(SUMMARY.read_text())
    earliest = summary["earliest"]
    expires = dt.datetime.fromisoformat(earliest["notAfter"])
    now = dt.datetime.now(dt.timezone.utc)
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=dt.timezone.utc)
    days = (expires - now).days
    if days > WARN_DAYS:
        return 0
    level = "EXPIRED" if days < 0 else ("URGENT" if days <= URGENT_DAYS else "soon")
    print(
        f"• certificates {level}: {earliest['path']} expires {earliest['notAfter']} "
        f"({days} days). Renew with `kdn-certs apply`, then `kdnctl host ensure ssh-host-certs --all --upload`.",
        file=sys.stderr,
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--check", action="store_true", help="exit 1 when the summary is stale"
    )
    group.add_argument(
        "--remind", action="store_true", help="print a warning when expiry is close"
    )
    args = parser.parse_args()
    if args.check:
        return check()
    if args.remind:
        return remind()
    return write()


if __name__ == "__main__":
    sys.exit(main())
