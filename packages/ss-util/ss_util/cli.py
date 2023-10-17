import base64
import json
import subprocess
import sys

import click
import secretstorage
import structlog

import contextlib

from secretstorage import util as ssu

from . import configure

configure.logging()
logger: structlog.stdlib.BoundLogger = structlog.get_logger()


@click.group(
    context_settings={"show_default": True},
)
def main():
    pass


def mk_tags(
    name: str,
    data: dict,
    ignore_lists=True,
    sep=":",
    ignored_keys: tuple[str, ...] = ("secret",),
):
    def _iter(path: str, value):
        if isinstance(value, dict):
            for key, value in value.items():
                if key in ignored_keys:
                    continue
                yield from _iter(f"{path}{sep}{key}", value)
            return
        if isinstance(value, list):
            if ignore_lists:
                return
            for i, value in enumerate(value):
                yield from _iter(f"{path}{sep}{i}", value)
            return
        yield path, value

    ignored_keys = set(ignored_keys)
    return dict(_iter(name, data))


def get_all_aliases(connection: secretstorage.DBusConnection):
    """Returns a generator of all available collections."""
    service = ssu.DBusAddressWrapper(ssu.SS_PATH, ssu.SERVICE_IFACE, connection)
    for collection_path in service.get_property("Collections"):
        yield secretstorage.Collection(connection, collection_path)


@main.command()
@click.option("--filename", "-f", default="")
@click.option("--pass-path", "-p", default="")
def dump(filename, pass_path):
    data = []

    def dump_item(item: secretstorage.Item):
        it = {
            "label": item.get_label(),
            "secret": base64.b64encode(item.get_secret()).decode(),
            "content_type": item.get_secret_content_type(),
            "attributes": item.get_attributes(),
            "metadata": {
                "path": item.item_path,
                "created": item.get_created(),
                "modified": item.get_modified(),
            },
        }
        with structlog.contextvars.bound_contextvars(**mk_tags("item", it)):
            logger.info("found an item")
        return it

    with contextlib.closing(secretstorage.dbus_init()) as connection:
        for collection in secretstorage.get_all_collections(connection):
            col = {
                "label": collection.get_label(),
                "metadata": {
                    "path": collection.collection_path,
                },
            }
            data.append(col)
            with structlog.contextvars.bound_contextvars(**mk_tags("collection", col)):
                logger.info("found a collection")
                col["items"] = list(map(dump_item, collection.get_all_items()))

    if pass_path:
        logger.info(f"dumping to `pass` at {pass_path}")
        subprocess.run(
            ["pass", "insert", "--force", "--multiline", pass_path],
            input=json.dumps(data, indent=2).encode(),
        )
    elif filename:
        logger.info(f"dumping to {filename}")
        with open(filename, "w") as f:
            json.dump(data, f, indent=2)
    else:
        logger.info(f"dumping to stdout")
        json.dump(data, sys.stdout, indent=2)


@main.command()
@click.option("--filename", "-f", default="")
@click.option("--pass-path", "-p", default="")
def restore(filename, pass_path):
    if pass_path:
        logger.info(f"restoring from `pass` at {pass_path}")
        data = json.loads(subprocess.check_output(["pass", "show", pass_path]))
    elif filename:
        logger.info(f"restoring from file {filename}")
        with open(filename, "rb") as fp:
            data = json.load(fp)
    else:
        logger.info(f"restoring from stdin")
        data = json.load(sys.stdin)

    def load_item(
        collection: secretstorage.Collection,
        items: dict[str, secretstorage.Item],
        it: dict,
    ):
        secret = base64.b64decode(it.pop("secret"))
        attrs = it.pop("attributes")
        label = it["label"]
        with structlog.contextvars.bound_contextvars(**mk_tags("item", it)):
            if label in items:
                logger.warning("item found")
                if not click.confirm(
                    f"item {label!r} already exists, do you want to override it?"
                ):
                    return
            else:
                logger.info("creating missing item")
            collection.create_item(
                label=label,
                attributes=attrs,
                secret=secret,
                replace=True,
                content_type=it["content_type"],
            )

    with contextlib.closing(secretstorage.dbus_init()) as connection:
        collections: dict[str, secretstorage.Collection] = {
            collection.get_label(): collection
            for collection in secretstorage.get_all_collections(connection)
        }
        for col in data:
            its: list = col.pop("items")
            label = col["label"]
            alias = ""
            if "default" in label:
                alias = "default"
            with structlog.contextvars.bound_contextvars(**mk_tags("collection", col)):
                collection = collections.get(label)
                if collection:
                    logger.warning("collection already exists")
                else:
                    logger.info("creating missing collection")
                    collection = secretstorage.create_collection(
                        connection,
                        label=label,
                        alias=alias,
                    )
                items: dict[str, secretstorage.Item] = {
                    item.get_label(): item for item in collection.get_all_items()
                }
                for it in its:
                    load_item(collection, items, it)


if __name__ == "__main__":
    main(
        auto_envvar_prefix="SS_UTIL",
    )
