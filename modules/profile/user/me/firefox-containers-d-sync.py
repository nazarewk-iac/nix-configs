import json
import logging
import sys
from pathlib import Path

logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.DEBUG)


def iter_files(profile: Path):
    file = profile / "containers.json"
    confd = profile / "containers.json.d"

    if file.exists():
        yield file, json.loads(file.read_bytes())
    for p in confd.glob("*.json"):
        yield p, json.loads(p.read_bytes())


def main(_, profile_path: Path):
    profile = Path(profile_path)
    logging.info(f"Processing {profile}")
    output = profile / "containers.json"

    identities = {}
    last_context_id: int = 0
    for path, entry in iter_files(profile):
        logging.info(f"Reading {path}")
        context_id = entry.get("lastUserContextId", -1)
        if context_id > last_context_id:
            logging.info(f'{profile}["lastUserContextId"] = {context_id=}')
            last_context_id = context_id

        for identity in entry.get("identities", []):
            iid = identity["userContextId"]
            if identity.get("public") and iid > last_context_id:
                logging.info(f'{profile}["lastUserContextId"] = {iid=}')
                last_context_id = iid
            existed = iid in identities
            old = identities.setdefault(iid, {})
            for key, new_value in identity.items():
                old_value = old.get(key)
                if old_value == new_value:
                    continue
                if existed:
                    logging.info(f"{profile}[{iid=}][{key=}]: "
                                 f"{old_value=} -> {new_value=}")
                old[key] = new_value

    if identities:
        output.write_text(json.dumps({
            "version": 5,
            "lastUserContextId": last_context_id,
            "identities": sorted(
                identities.values(),
                key=lambda ident: ident["userContextId"]
            ),
        }))


if __name__ == '__main__':
    main(*sys.argv)
