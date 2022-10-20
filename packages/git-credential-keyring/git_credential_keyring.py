import sys

import keyring


def main():
    params = {
        (tokens := line.strip().split("=", 1))[0]: tokens[1]
        for line in sys.stdin
        if '=' in line
    }

    url = "%(protocol)s://%(host)s" % params
    if "path" in params:
        url = "/".join((url, params["path"]))

    service = "git-credential-keyring+" + url

    match sys.argv[-1]:
        case "get":
            username = params.get("username")
            if hasattr(keyring, "get_credential"):
                credential = keyring.get_credential(service, username)
                if credential is None:
                    sys.exit()

                username = credential.username
                password = credential.password
            else:
                password = keyring.get_password(service, username)
                if password is None:
                    sys.exit()

            if "username" not in params and username is not None:
                print("username=" + username)
            print("password=" + password)

        case "store":
            keyring.set_password(service, params["username"], params["password"])

        case "erase":
            keyring.delete_password(service, params["username"])

        case _:
            print("Invalid usage", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
