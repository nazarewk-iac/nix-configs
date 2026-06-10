"""
Update flake.lock using a reference lock from a jj revision.

Reads flake.lock from the given jj revision, writes it to a temp file,
then runs `nix flake lock --reference-lock-file` to preserve pinned inputs
from that reference where they match current flake inputs.

Usage:
  flake-lock-merge [options] <revision>
"""

import argparse
import os
import subprocess
import sys
import tempfile


def get_jj_lock(rev: str, path: str) -> bytes:
    result = subprocess.run(
        ["jj", "file", "show", "--revision", rev, path],
        capture_output=True, check=True,
    )
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("revision", help="jj revision to use as reference lock")
    parser.add_argument("--path", default="flake.lock", help="Path within the jj tree (default: flake.lock)")
    parser.add_argument("--update-input", "-u", action="append", dest="update_inputs", metavar="INPUT",
                        help="Pass --update-input to nix flake lock (repeatable)")
    args = parser.parse_args()

    print(f"Loading reference lock from jj revision: {args.revision}", file=sys.stderr)
    lock_data = get_jj_lock(args.revision, args.path)

    with tempfile.NamedTemporaryFile(suffix=".lock", delete=False) as tmp:
        tmp.write(lock_data)
        tmp_path = tmp.name

    try:
        cmd = ["nix", "flake", "lock", "--reference-lock-file", tmp_path]
        for inp in (args.update_inputs or []):
            cmd += ["--update-input", inp]
        print(f"Running: {' '.join(cmd)}", file=sys.stderr)
        subprocess.run(cmd, check=True)
    finally:
        os.unlink(tmp_path)


if __name__ == "__main__":
    main()
