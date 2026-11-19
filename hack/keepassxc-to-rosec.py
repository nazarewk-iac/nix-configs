#!/usr/bin/env python3
"""Copy the live Secret Service items into a rosec provider.

The source is the running Secret Service daemon (KeePassXC today, rosec after
the cutover), read through the standard D-Bus interfaces.  The destination is
another Secret Service daemon (a private ``rosecd`` during the migration).
Both are addressed by bus address, so the two daemons never share a bus.

Every public attribute is copied verbatim.  That matters: the attributes are
the search contract the clients use (``secret-tool lookup xdg:schema ...``), and
rosec's attributes are already as public as KeePassXC's are on D-Bus, so the
copy adds no exposure.  The secret is copied as raw bytes; a non-UTF-8 secret
becomes a base64 secret.

Usage::

    # report only, no writes
    python3 hack/keepassxc-to-rosec.py --from "$DBUS_SESSION_BUS_ADDRESS" --dry-run

    # copy into a private rosecd, then verify through the client interface
    python3 hack/keepassxc-to-rosec.py \
        --from "$DBUS_SESSION_BUS_ADDRESS" --to "unix:path=/run/user/1000/rosec-mig/bus" \
        --migrate --report "$STAGE/migrate.json"

The tool never prints a secret.  The report carries labels, attribute names,
secret lengths and pass/fail only.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field

SECRET_NAME = "password"
ITEM_TYPE = "login"
UUID_ATTR = "Uuid"
ITEM_IFACE = "org.freedesktop.Secret.Item"
COLLECTION_IFACE = "org.freedesktop.Secret.Collection"
SERVICE_PATH = "/org/freedesktop/secrets"


def q(value: str) -> str:
    """Quote a TOML basic string or key.

    ``json.dumps`` with ``ensure_ascii=False`` emits exactly the escapes a TOML
    basic string accepts (``\\n``, ``\\t``, ``\\uXXXX``, ``\\"``, ``\\\\``), and
    leaves non-ASCII as the characters themselves, so no surrogate pairs appear.
    """
    return json.dumps(value, ensure_ascii=False)


@dataclass
class Item:
    uuid: str
    label: str
    attributes: dict[str, str] = field(default_factory=dict)
    secret: bytes = b""

    @property
    def toml(self) -> str:
        lines = [
            "[item]",
            f"label = {q(self.label)}",
            f'type = "{ITEM_TYPE}"',
            "",
            "[attributes]",
        ]
        # rosec drops empty attribute values on import, so do not emit them.
        for key, value in sorted(self.attributes.items()):
            if value == "":
                continue
            lines.append(f"{q(key)} = {q(value)}")
        lines += ["", "[secrets]"]
        if self.secret:
            try:
                text = self.secret.decode("utf-8")
            except UnicodeDecodeError:
                encoded = base64.b64encode(self.secret).decode("ascii")
                lines.append(f'{q(SECRET_NAME)} = {{ base64 = "{encoded}" }}')
            else:
                lines.append(f"{q(SECRET_NAME)} = {q(text)}")
        return "\n".join(lines) + "\n"


def busctl(bus: str, path: str, iface: str, prop: str, attempts: int = 3):
    """Read one D-Bus property as JSON.

    ``busctl`` reports a stale object path as an error while a daemon rebuilds
    its object tree, so retry a few times.
    """
    last = ""
    for _ in range(attempts):
        cp = subprocess.run(
            [
                "busctl",
                "--address",
                bus,
                "--json=short",
                "call",
                "org.freedesktop.secrets",
                path,
                "org.freedesktop.DBus.Properties",
                "Get",
                "ss",
                iface,
                prop,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if cp.returncode == 0:
            return json.loads(cp.stdout)["data"][0]["data"]
        last = cp.stderr.strip()
    raise RuntimeError(f"reading {iface}.{prop} at {path} failed: {last}")


def read_secret(bus: str, uuid: str) -> bytes:
    """Read an item secret through the client interface (libsecret).

    ``secret-tool`` matches attributes; the entry UUID is unique per item and
    present in both daemons, so it is the stable key.  The output is the raw
    secret with no trailing newline.
    """
    cp = subprocess.run(
        ["secret-tool", "lookup", UUID_ATTR, uuid],
        capture_output=True,
        check=False,
        env={**os.environ, "DBUS_SESSION_BUS_ADDRESS": bus},
    )
    if cp.returncode != 0:
        raise RuntimeError(
            f"secret-tool lookup {UUID_ATTR}={uuid} exited {cp.returncode}"
        )
    return cp.stdout


def read_items(bus: str) -> list[Item]:
    """Read every item from every collection on ``bus``."""
    items: list[Item] = []
    collections = busctl(
        bus, SERVICE_PATH, "org.freedesktop.Secret.Service", "Collections"
    )
    for collection in collections:
        for path in busctl(bus, collection, COLLECTION_IFACE, "Items"):
            attributes = busctl(bus, path, ITEM_IFACE, "Attributes")
            uuid = attributes.get(UUID_ATTR, "")
            if not uuid:
                raise RuntimeError(f"item {path} has no {UUID_ATTR} attribute")
            label = attributes.get("Title") or uuid
            items.append(Item(uuid, label, dict(attributes), read_secret(bus, uuid)))
    return items


def socket_path(bus: str) -> str | None:
    """Return the socket path of a ``unix:path=`` bus address."""
    if bus.startswith("unix:path="):
        return bus[len("unix:path=") :].split(",", 1)[0]
    return None


def run_rosec(bus: str, *args: str, stdin: str | None = None):
    """Run a rosec CLI command against ``bus``.

    `rosec` resolves `ROSEC_SOCKET` before the session bus, so an inherited
    value would silently retarget the command; pin it (or clear it) every call.
    """
    env = {**os.environ, "DBUS_SESSION_BUS_ADDRESS": bus}
    path = socket_path(bus)
    if path:
        env["ROSEC_SOCKET"] = path
    else:
        env.pop("ROSEC_SOCKET", None)
    return subprocess.run(
        ["rosec", *args],
        input=stdin,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )


def validate(items: list[Item]) -> list[str]:
    """Re-parse every emitted TOML; return the labels that failed."""
    bad: list[str] = []
    for item in items:
        try:
            parsed = tomllib.loads(item.toml)
        except tomllib.TOMLDecodeError:
            bad.append(item.label)
            continue
        attrs = parsed.get("attributes", {})
        secrets = parsed.get("secrets", {})
        if item.uuid not in (v for v in attrs.values()):
            bad.append(item.label)
        elif item.secret and SECRET_NAME not in secrets:
            bad.append(item.label)
    return bad


def describe(items: list[Item]) -> dict:
    attr_names: dict[str, int] = {}
    for item in items:
        for name in item.attributes:
            attr_names[name] = attr_names.get(name, 0) + 1
    return {
        "count": len(items),
        "attribute_names": dict(sorted(attr_names.items())),
        "empty_secrets": len([i for i in items if not i.secret]),
        "binary_secrets": len([i for i in items if not is_utf8(i.secret)]),
        "max_secret_len": max((len(i.secret) for i in items), default=0),
        "total_secret_len": sum(len(i.secret) for i in items),
    }


def is_utf8(value: bytes) -> bool:
    try:
        value.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def write_report(path: str | None, data: dict) -> None:
    """Write the report atomically: an interrupted run must not leave half a JSON file."""
    if not path:
        return
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def contact_sheet(items: list[Item], statuses: dict[str, str]) -> dict:
    return {
        "items": [
            {
                "uuid": item.uuid,
                "label": item.label,
                "attribute_names": sorted(
                    name for name, value in item.attributes.items() if value
                ),
                "secret_len": len(item.secret),
                "status": statuses.get(item.uuid, "unknown"),
            }
            for item in items
        ]
    }


def dry_run(items: list[Item]) -> int:
    info = describe(items)
    bad = validate(items)
    print(
        f"dry-run: {info['count']} items, {info['binary_secrets']} binary secrets, "
        f"{info['empty_secrets']} empty secrets, largest {info['max_secret_len']} bytes; no writes"
    )
    print(f"dry-run: attribute names: {', '.join(info['attribute_names'])}")
    if bad:
        print(
            f"dry-run: {len(bad)} items emit TOML that does not round-trip",
            file=sys.stderr,
        )
        return 1
    return 0


def apply(
    items: list[Item], dest_bus: str, provider: str
) -> tuple[dict[str, str], dict]:
    statuses: dict[str, str] = {}
    errors: list[dict] = []
    imported = 0
    for item in items:
        if not item.secret:
            statuses[item.uuid] = "skipped: empty secret"
            continue
        # `item import --force` only replaces byte-equal secrets, so remove the
        # previous copy first.  The delete fails when the item is absent, which
        # is the normal first run.
        run_rosec(dest_bus, "item", "delete", "-y", f"{UUID_ATTR}={item.uuid}")
        cp = run_rosec(
            dest_bus, "item", "import", "--provider", provider, stdin=item.toml
        )
        if cp.returncode != 0:
            # The report never carries the command's text: a parser error can quote the input.
            statuses[item.uuid] = "error: import failed"
            errors.append(
                {
                    "uuid": item.uuid,
                    "label": item.label,
                    "error": f"import exited {cp.returncode}",
                }
            )
        else:
            statuses[item.uuid] = "imported"
            imported += 1
    return statuses, {"errors": errors, "imported": imported}


def check(items: list[Item], dest_bus: str, statuses: dict[str, str]) -> dict:
    destination: dict[str, Item] = {}
    for item in read_items(dest_bus):
        destination[item.uuid] = item
    mismatches: list[dict] = []
    missing: list[str] = []
    for item in items:
        found = destination.get(item.uuid)
        if found is None:
            missing.append(item.uuid)
            statuses[item.uuid] = "missing"
            continue
        fields: list[str] = []
        if found.label != item.label:
            fields.append("label")
        for name, value in item.attributes.items():
            if value and found.attributes.get(name) != value:
                fields.append(f"attributes.{name}")
        if found.secret != item.secret:
            fields.append(f"secrets.{SECRET_NAME}")
        if fields:
            mismatches.append(
                {"uuid": item.uuid, "label": item.label, "fields": fields}
            )
            if not statuses.get(item.uuid, "").startswith("error"):
                statuses[item.uuid] = "mismatch"
        else:
            # A failed import must stay visible even when the destination happens
            # to already match (the delete-then-import run reports it).
            if not statuses.get(item.uuid, "").startswith("error"):
                statuses[item.uuid] = "matched"
    # Items the destination holds but the source does not: pre-existing data, reported, not failed.
    extra = sorted(set(destination) - {item.uuid for item in items})
    return {"missing": missing, "mismatches": mismatches, "extra": extra}


SELF_TEST_ITEMS = [
    Item(
        "00112233445566778899aabbccddeeff",
        'login "quoted" — ünïcode 🎉',
        {
            "Uuid": "00112233445566778899aabbccddeeff",
            "Title": 'login "quoted" — ünïcode 🎉',
            "UserName": "alice",
            "URL": "https://example.test",
            "xdg:schema": "org.gnome.keyring.NetworkPassword",
            "service": "",
            "Notes": "line one\nline two\ttabbed",
        },
        b"pw-with-\n-newline",
    ),
    Item(
        "ffeeddccbbaa99887766554433221100",
        "binary",
        {"Uuid": "ffeeddccbbaa99887766554433221100", "Title": "binary"},
        bytes([0x00, 0xFF, 0x10, 0x80]),
    ),
]


def self_test() -> int:
    for item in SELF_TEST_ITEMS:
        parsed = tomllib.loads(item.toml)
        assert parsed["item"]["label"] == item.label, item.label
        assert parsed["item"]["type"] == ITEM_TYPE
        assert parsed["attributes"]["Uuid"] == item.uuid
        assert "service" not in parsed["attributes"], "empty attribute must be dropped"
    text_item, binary_item = SELF_TEST_ITEMS
    parsed_text = tomllib.loads(text_item.toml)
    assert parsed_text["attributes"]["Notes"] == "line one\nline two\ttabbed", (
        "notes are public attributes"
    )
    assert (
        parsed_text["attributes"]["xdg:schema"] == "org.gnome.keyring.NetworkPassword"
    )
    assert parsed_text["secrets"][SECRET_NAME] == "pw-with-\n-newline"
    binary = tomllib.loads(binary_item.toml)["secrets"][SECRET_NAME]
    assert base64.b64decode(binary["base64"]) == binary_item.secret
    assert validate(SELF_TEST_ITEMS) == [], validate(SELF_TEST_ITEMS)
    print("self-test: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--from",
        dest="source_bus",
        default=os.environ.get("DBUS_SESSION_BUS_ADDRESS", ""),
    )
    parser.add_argument(
        "--to", dest="dest_bus", default=os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    )
    parser.add_argument(
        "--provider", default="sops", help="rosec provider id (default: sops)"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="read the source and report; no writes"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="delete by Uuid, then import into the destination",
    )
    parser.add_argument(
        "--check", action="store_true", help="compare the destination with the source"
    )
    parser.add_argument("--migrate", action="store_true", help="--apply, then --check")
    parser.add_argument("--report", help="write a JSON report")
    parser.add_argument(
        "--self-test", action="store_true", help="run the built-in mapping self-test"
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.source_bus:
        parser.error("--from or DBUS_SESSION_BUS_ADDRESS is required")
    if not (args.dry_run or args.apply or args.check or args.migrate):
        parser.error("one of --dry-run, --apply, --check or --migrate is required")
    if (args.apply or args.migrate or args.check) and not args.dest_bus:
        parser.error("--to or DBUS_SESSION_BUS_ADDRESS is required")
    if (args.apply or args.migrate or args.check) and args.source_bus == args.dest_bus:
        parser.error(
            "--from and --to are the same bus; a copy into itself proves nothing"
        )

    items = read_items(args.source_bus)
    if args.dry_run:
        write_report(args.report, describe(items))
        return dry_run(items)

    if args.apply or args.migrate:
        # Parse every emitted TOML before the first write: a bad mapping must not
        # half-populate the store.
        bad = validate(items)
        if bad:
            print(
                f"error: {len(bad)} items emit TOML that does not round-trip; no writes",
                file=sys.stderr,
            )
            return 1

    statuses: dict[str, str] = {}
    report: dict = {"source": describe(items)}
    if args.apply or args.migrate:
        statuses, details = apply(items, args.dest_bus, args.provider)
        report["apply"] = details
    if args.check or args.migrate:
        result = check(items, args.dest_bus, statuses)
        report["check"] = result
        if result["missing"] or result["mismatches"]:
            print(
                f"check: {len(result['missing'])} missing, {len(result['mismatches'])} mismatched",
                file=sys.stderr,
            )
            write_report(args.report, {**report, **contact_sheet(items, statuses)})
            return 1
        print(f"check: {len(items)} items match the source")
        if result["extra"]:
            print(
                f"check: {len(result['extra'])} destination items are not in the source"
            )
    if args.apply or args.migrate:
        # The authoritative failure list comes from the apply step, not from the
        # status map: the check would otherwise mask a failed import.
        failed = report.get("apply", {}).get("errors", [])
        if failed:
            print(f"apply: {len(failed)} imports failed", file=sys.stderr)
            write_report(args.report, {**report, **contact_sheet(items, statuses)})
            return 1
        print(f"apply: {report.get('apply', {}).get('imported', 0)} items imported")
    write_report(args.report, {**report, **contact_sheet(items, statuses)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
