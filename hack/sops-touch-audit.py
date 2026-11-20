#!/usr/bin/env python3
"""Which sops files still need a YubiKey touch?

Every encrypted file lists its recipients in its own `sops:` metadata. This maps those public keys
back to the anchors in `.sops.yaml`, classifies each recipient as unattended (a plain age host key,
an ssh key, or a `*-unattended` YubiKey identity) or touch-required (`*-touch`), and reports:

  1. every creation rule from `.sops.yaml`, with its recipients classified;
  2. every encrypted file whose recipients are all touch-required, i.e. a machine cannot decrypt it
     without a human present.

Run it from the repository root.
"""
import re
import subprocess
from pathlib import Path

SOPS = Path(".sops.yaml")


def anchors():
    """name -> public key, from the YAML anchors in .sops.yaml."""
    text = SOPS.read_text()
    return {
        m.group(1): m.group(2)
        for m in re.finditer(r"&([\w.-]+)\s+([A-Za-z0-9+/=_-]+)", text)
    }


def kind(name):
    if name.endswith("-unattended"):
        return "unattended"
    if name.endswith("-touch"):
        return "touch"
    if name.startswith("age-") or name.startswith("ssh-"):
        return "unattended"
    return "other"


def rules():
    """(path_regex, [anchor names]) for each creation rule, in file order."""
    text = SOPS.read_text()
    out = []
    for m in re.finditer(r"- path_regex:\s*'([^']+)'\n\s+key_groups:(.*?)(?=\n  - path_regex:|\Z)",
                         text, re.S):
        names = re.findall(r"\*([\w.-]+)", m.group(2))
        out.append((m.group(1), names))
    return out


def file_recipients(path):
    """The public keys a file is encrypted to, from its own sops metadata."""
    text = path.read_text(errors="ignore")
    idx = text.find("\nsops:")
    if idx < 0:
        return None
    tail = text[idx:]
    return sorted(set(re.findall(r"age1[a-z0-9]{20,}", tail)))


def main():
    a = anchors()
    by_key = {v: k for k, v in a.items()}

    print("== creation rules in .sops.yaml ==\n")
    for regex, names in rules():
        kinds = {kind(n) for n in names}
        verdict = "UNATTENDED OK" if "unattended" in kinds else "TOUCH ONLY"
        print(f"  {verdict:14} {regex}")
        print("     " + ", ".join(f"{n}[{kind(n)}]" for n in names))

    print("\n== encrypted files whose recipients are all touch-required ==\n")
    files = subprocess.run(
        ["git", "ls-files", "*sops*.yaml", "*sops*.yml", "*sops*.json"],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    touch_only, mixed, clean = [], [], 0
    for f in files:
        p = Path(f)
        rec = file_recipients(p)
        if not rec:
            continue
        names = [by_key.get(k, k[:18] + "…") for k in rec]
        kinds = {kind(n) for n in names}
        if "touch" in kinds and "unattended" not in kinds:
            touch_only.append((f, names))
        elif "touch" in kinds:
            mixed.append((f, names))
        else:
            clean += 1

    for f, names in touch_only:
        print(f"  TOUCH ONLY  {f}")
        print(f"              {', '.join(names)}")
    if not touch_only:
        print("  (none)")
    print(f"\n  files with a mix of touch and unattended recipients: {len(mixed)}")
    for f, names in mixed:
        print(f"     {f}: {', '.join(names)}")
    print(f"  files decryptable with no touch at all: {clean}")


main()
