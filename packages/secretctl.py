# !/usr/bin/env python3

# based on https://gist.github.com/grawity/0a14176e90fde7697538f3f9216ec01a

import argparse
import base64
import datetime
import gi
import json
import sys

gi.require_version("Secret", "1")
from gi.repository import Gio, Secret


def _encode_default(obj):
    if type(obj) in {bytes, bytearray}:
        return {"#type": "bytes",
                "#value": base64.b64encode(obj).decode()}
    elif type(obj) in {set, frozenset}:
        return {"#type": "set",
                "#value": [*obj]}
    elif type(obj) == datetime.datetime:
        return {"#type": "datetime",
                "#value": obj.isoformat()}
    else:
        raise TypeError("object of type '%s' is not JSON-serializable" % type(obj))


def _decode_object_hook(obj):
    if len(obj) == 2 and {*obj} == {"#type", "#value"}:
        hint = obj["#type"]
        if hint == "bytes":
            return base64.b64decode(obj["#value"])
        elif hint == "set":
            return set(obj["#value"])
        elif hint == "datetime":
            return datetime.datetime.fromisoformat(obj["#value"])
        else:
            raise ValueError("unrecognized type hint %r in object %r" % (hint, obj))
    else:
        return obj


def json_dump(data, **kwargs):
    return json.dumps(data, **kwargs, default=_encode_default)


def json_load(data, **kwargs):
    return json.loads(data, **kwargs, object_hook=_decode_object_hook)


def dump_entries2():
    service = Secret.Service.get_sync(0, Gio.Cancellable())
    service.load_collections_sync()
    collections = service.get_collections()
    data = {}
    for coll in collections:
        c_name = coll.get_object_path().split("/")[-1]
        if c_name == "session":
            continue
        if coll.get_locked():
            print(f"Skipping collection {c_name!r} as it is locked",
                  file=sys.stderr)
            continue
        c_label = coll.get_label()
        c_items = coll.get_items()
        print(f"Dumping collection {c_name!r} ({len(c_items)} items)",
              file=sys.stderr)
        data[c_name] = {"label": c_label,
                        "items": []}
        for item in c_items:
            item.load_secret_sync()
            i_label: str = item.get_label()
            i_secret: bytes = item.get_secret().get()
            i_attrs: dict = item.get_attributes()
            data[c_name]["items"].append({"label": i_label,
                                          "secret": i_secret,
                                          "attrs": i_attrs})
    return data


def dump_entries(data):
    data = {"login": {"label": "Login",
                      "items": []}}
    items = Secret.password_search_sync(None,
                                        {},
                                        Secret.SearchFlags.ALL |
                                        Secret.SearchFlags.LOAD_SECRETS,
                                        None)
    for item in items:
        data["login"]["items"].append({"label": item.get_label(),
                                       "secret": item.get_secret().get(),
                                       "attrs": item.get_attributes(),
                                       "created": item.get_created(),
                                       "updated": item.get_modified()})
    return data


def load_entries(data):
    for c_name, coll in data.items():
        c_label = coll["label"]
        for item in coll["items"]:
            i_label = item["label"]
            i_secret = item["secret"]
            i_attrs = item["attrs"]
            print(f"Creating item: \"{i_label}\"")
            schema = None
            collection = None
            if type(i_secret) == bytes:
                Secret.password_store_binary_sync(
                    schema,
                    attrs,
                    collection,
                    i_label,
                    i_secret)
            else:
                Secret.password_store_sync(
                    schema,
                    attrs,
                    collection,
                    i_label,
                    i_secret)


parser = argparse.ArgumentParser()
parser.add_argument("-o", "--dump", action="store_true")
parser.add_argument("-i", "--load", action="store_true")
args = parser.parse_args()

if (args.dump + args.load) > 1:
    exit("error: Conflicting options given.")
elif args.dump:
    data = dump_entries()
    print(json_dump(data))
elif args.load:
    data = json_load(sys.stdin.read())
    load_entries(data)
else:
    exit("error: Operation not specified.")
