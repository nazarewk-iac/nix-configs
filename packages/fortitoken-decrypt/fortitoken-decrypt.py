#!/usr/bin/env python3
# requires a rooted Android phone
# based off https://jonstoler.me/blog/extracting-fortitoken-mobile-totp-secret
import sys
import time

import base64
import functools
import hashlib
import re
import subprocess
import xml.etree.ElementTree as ET
from Crypto.Cipher import AES


def unpad(s):
    return s[0 : -ord(s[-1])]


def decrypt(cipher, key):
    sha256 = hashlib.sha256()
    sha256.update(bytes(key, "utf-8"))
    digest = sha256.digest()
    iv = bytes([0] * 16)
    aes = AES.new(digest, AES.MODE_CBC, iv)
    decrypted = aes.decrypt(base64.b64decode(cipher))
    return unpad(str(decrypted, "utf-8"))


def adb_call(*cmd, **kwargs):
    subprocess.check_call(["adb", *cmd], **kwargs)


def shell_out(*cmd, **kwargs):
    return subprocess.check_output(["adb", "shell", *cmd], **kwargs)


@functools.cache
def adb_server(device):
    subprocess.check_call(["adb", "kill-server"])
    time.sleep(1.0)
    subprocess.check_call(["adb", "--one-device", device, "start-server"])


@functools.cache
def adb_root():
    subprocess.check_call(["adb", "root"])


@functools.cache
def get_seed(token_name):
    out = shell_out(
        "sqlite3",
        "/data/data/com.fortinet.android.ftm/databases/FortiToken.db",
        input=f'SELECT seed FROM Account WHERE type="totp" AND name="{token_name}";'.encode(),
    )
    return out.decode().strip()


@functools.cache
def get_shared_prefs():
    xml = shell_out(
        "cat",
        "/data/data/com.fortinet.android.ftm/shared_prefs/FortiToken_SharedPrefs_NAME.xml",
    ).decode()
    tree = ET.fromstring(xml)
    return tree


@functools.cache
def get_ssaid():
    xml = shell_out(
        "cat",
        "/data/system/users/0/settings_ssaid.xml",
    ).decode()
    # see https://stackoverflow.com/a/38854127
    # xml.etree.ElementTree.ParseError: junk after document element: line 86, column 0
    xml = re.sub(r"(<\?xml[^>]+\?>)", r"\1<root>", xml) + "</root>"
    tree = ET.fromstring(xml)
    return tree


@functools.cache
def get_uuid():
    prefs = get_shared_prefs()
    return prefs.find("string[@name='UUID']").text


@functools.cache
def get_device_id():
    setting = get_ssaid().find(".//setting[@package='com.fortinet.android.ftm']")
    return setting.attrib["value"]


@functools.cache
def get_serial():
    return get_shared_prefs().find("string[@name='SerialNumberPreAndroid9']").text


def main():
    try:
        device_id = sys.argv[1]
        token_name = sys.argv[2]
    except IndexError:
        print("the script requires 2 arguments: ADB_DEVICE_ID and FORTITOKEN_NAME")
        print("ADB_DEVICE_ID: from `adb devices -l`, example: 'a1b2c3d4'")
        print("FORTITOKEN_NAME: read from application, example: 'FortiToken 1234'")
        sys.exit(1)
    adb_server(device_id)
    adb_root()
    uuid_key = get_device_id() + get_serial()[11:]
    print("UUID KEY: %s" % uuid_key)
    decoded_uuid = decrypt(get_uuid(), uuid_key)
    print("UUID: %s" % decoded_uuid)

    seed_decryption_key = uuid_key + decoded_uuid
    print("SEED KEY: %s" % seed_decryption_key)
    decrypted_seed = decrypt(get_seed(token_name), seed_decryption_key)

    totp_secret = bytes.fromhex(decrypted_seed)

    totp_secret_encoded = str(base64.b32encode(totp_secret), "utf-8")
    print("TOTP SECRET: %s" % totp_secret_encoded)


if __name__ == "__main__":
    main()
