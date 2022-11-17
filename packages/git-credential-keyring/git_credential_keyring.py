import sys

import keyring


def get(service: str, username: str):
    if hasattr(keyring, "get_credential"):
        credential = keyring.get_credential(service, username)
        if credential is None:
            sys.exit()

        username = credential.username
        password = credential.password
    else:
        password = keyring.get_password(service, username)
    return username, password


def main():
    params = {
        (tokens := line.strip().split("=", 1))[0]: tokens[1]
        for line in sys.stdin
        if '=' in line
    }

    protocolless_url = params["host"]
    if "path" in params:
        protocolless_url = "/".join((protocolless_url, params["path"]))

    deprecated_services = [
        # this scheme has trouble syncing on Android (Permission Denied) most likely due to either + or : sign
        f"git-credential-keyring+%(protocol)s://{protocolless_url}" % params,
    ]

    service = "git/" + protocolless_url
    username = params.get("username")
    password = params.get("password")

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
            print("password=" + password)

        case "store":
            keyring.set_password(service, username, password)

        case "erase":
            keyring.delete_password(service, username)

        case _:
            print("Invalid usage", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
