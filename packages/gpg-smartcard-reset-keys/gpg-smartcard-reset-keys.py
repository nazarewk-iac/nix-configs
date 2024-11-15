import logging
import os
import subprocess
from pathlib import Path

logging.basicConfig(format="%(levelname)s:%(message)s", level=logging.DEBUG)
gpg_home = Path(os.environ.get("GNUPGHOME") or Path.home() / ".gnupg")

card_status_lines = subprocess.check_output(
    ["gpg", "--card-status"], encoding="utf8"
).splitlines()

short_fingerprints = set()
for idx, cur in enumerate(card_status_lines):
    cur = cur.strip()
    if not cur.startswith("card-no: "):
        continue
    prv = card_status_lines[idx - 1]
    short_fingerprints.add(prv.split()[1].split("/")[1].removeprefix("0x"))

is_match = False
keygrips = []
for line in subprocess.check_output(
    ["gpg", "--list-keys", "--with-colons", "--with-keygrip"], encoding="utf8"
).splitlines():
    cols = line.split(":")
    row_type = cols[0]
    if row_type == "sub":
        is_match = cols[4] in short_fingerprints
    elif is_match and row_type == "grp":
        keygrip = cols[9]
        keygrips.append(keygrip)
        is_match = False

pass
for keygrip in keygrips:
    priv_key = gpg_home / "private-keys-v1.d" / f"{keygrip}.key"
    logging.info(f"Clearing {priv_key}")
    priv_key.unlink(missing_ok=True)

subprocess.run(["gpg", "--card-status"])
