import hashlib
import json
import logging
import os
import sys

import keyring

logging.basicConfig(
    level=os.environ.get("GIT_CREDENTIAL_KEYRING_LOG_LEVEL") or logging.WARNING
)


def trim(component: str):
    # address filename too long issues
    # see https://en.wikipedia.org/wiki/Comparison_of_file_systems#Limits
    if len(component) > 255:
        component = f"sha256-{hashlib.sha256(component.encode()).hexdigest()}"
    return component


def normalize(service: str, username: str):
    return trim(service), trim(username)


def get(service: str, username: str):
    service, username = normalize(service, username)
    if hasattr(keyring, "get_credential"):
        credential = keyring.get_credential(service, username)
        if credential is None:
            sys.exit()

        username = credential.username
        password = credential.password
    else:
        password = keyring.get_password(service, username)
    return username, password


def set(service: str, username: str, password: str):
    service, username = normalize(service, username)
    keyring.set_password(service, username, password)


def delete(service: str, username: str):
    service, username = normalize(service, username)
    if os.environ.get("GIT_CREDENTIAL_KEYRING_IGNORE_DELETIONS", "") == "1":
        print(
            f"not deleting {username}@{service} because of $GIT_CREDENTIAL_KEYRING_IGNORE_DELETIONS == 1",
            file=sys.stderr,
        )
        return
    keyring.delete_password(service, username)


def main():
    params = {
        (tokens := line.strip().split("=", 1))[0]: tokens[1]
        for line in sys.stdin
        if "=" in line
    }
    logging.debug(f"{sys.argv}")
    logging.debug(json.dumps(params, indent=2))

    protocolless_url = params["host"]
    if "path" in params:
        protocolless_url = "/".join((protocolless_url, params["path"]))

    deprecated_services = [
        # this scheme has trouble syncing on Android (Permission Denied) most likely due to either + or : sign
        f"git-credential-keyring+%(protocol)s://{protocolless_url}"
        % params,
    ]

    service = "git/" + protocolless_url
    username = params.get("username", "")
    password = params.get("password", "")

    match sys.argv[-1]:
        case "get":
            username, password = get(service, username)

            if not password:
                for deprecated_service in deprecated_services:
                    username, password = get(deprecated_service, username)
                    if password:
                        keyring.set_password(service, username, password)
                        keyring.delete_password(deprecated_service, username)
                        break

            if "username" not in params and username is not None:
                print("username=" + username)
                logging.debug("username=" + username)
            print("password=" + password)
            logging.debug("password=" + password)

        case "store":
            set(service, username, password)

        case "erase":
            delete(service, username)

        case _:
            logging.error("Invalid usage")
            # helpers should silently ignore unknown commands.


if __name__ == "__main__":
    main()
