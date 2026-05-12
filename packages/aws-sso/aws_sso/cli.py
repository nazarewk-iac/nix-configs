import argparse
import configparser
import datetime
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

import boto3

LOGIN_MARGIN = datetime.timedelta(minutes=1)


def sso_login(session_name=None):
    cmd = ["aws", "sso", "login"]
    if session_name:
        cmd += ["--sso-session", session_name]
    print(f"Running: {' '.join(cmd)}", file=sys.stderr)
    subprocess.run(cmd, check=True)


def get_sso_token(session_name=None):
    cache_dir = os.path.expanduser("~/.aws/sso/cache")
    if session_name is not None:
        # AWS CLI v2 names the cache file sha1(session_name).json
        cache_files = [os.path.join(cache_dir, hashlib.sha1(session_name.encode()).hexdigest() + ".json")]
    else:
        cache_files = glob.glob(os.path.join(cache_dir, "*.json"))

    for f in cache_files:
        if not os.path.exists(f):
            continue
        data = json.load(open(f))
        if "accessToken" not in data:
            continue
        expires_at = datetime.datetime.fromisoformat(data["expiresAt"].replace("Z", "+00:00"))
        if expires_at - datetime.datetime.now(datetime.timezone.utc) >= LOGIN_MARGIN:
            return data["accessToken"]

    sso_login(session_name)

    for f in cache_files:
        if not os.path.exists(f):
            continue
        data = json.load(open(f))
        if "accessToken" in data:
            return data["accessToken"]

    hint = f" for session '{session_name}'" if session_name else ""
    raise RuntimeError(f"SSO login succeeded but no token found{hint}")


def get_session_region(session_name):
    config_path = os.path.expanduser("~/.aws/config")
    config = configparser.ConfigParser()
    config.read(config_path)
    section = f"sso-session {session_name}"
    if config.has_option(section, "sso_region"):
        return config.get(section, "sso_region")
    return None


def make_sso_client(session_name=None, region=None):
    if region is None and session_name:
        region = get_session_region(session_name)
    if region is None:
        region = "us-east-1"
    token = get_sso_token(session_name)
    client = boto3.client("sso", region_name=region)
    return token, client


def iter_accounts_with_roles(token, sso):
    for page in sso.get_paginator("list_accounts").paginate(accessToken=token):
        for account in page["accountList"]:
            account_id = account["accountId"]
            account_name = account["accountName"]
            roles = [
                role["roleName"]
                for rpage in sso.get_paginator("list_account_roles").paginate(
                    accountId=account_id, accessToken=token
                )
                for role in rpage["roleList"]
            ]
            yield account_id, account_name, roles


def to_kebab(s):
    return re.sub(r"[^a-z0-9-]+", "-", s.lower()).strip("-")


def to_name(*pieces):
    return "--".join(to_kebab(p) for p in pieces if p)


def profile_name(account_name, role, account_id, prefix=None):
    return to_name(prefix, account_name, role, account_id)


def cmd_list(args):
    token, sso = make_sso_client(args.session, args.region)
    for account_id, account_name, roles in iter_accounts_with_roles(token, sso):
        print(f"{account_name} ({account_id}): {', '.join(roles)}")


def block_in_file(path, content, block_id, marker_pattern="# {mark} {id}"):
    begin = marker_pattern.format(mark="BEGIN", id=block_id)
    end = marker_pattern.format(mark="END", id=block_id)
    block = begin + "\n" + content + "\n" + end

    original = open(path).read() if os.path.exists(path) else ""

    if begin in original:
        before = original[: original.index(begin)]
        after = original[original.index(end) + len(end):].lstrip("\n")
        new_content = before.rstrip("\n") + "\n\n" + block + ("\n\n" + after if after else "\n")
    else:
        new_content = original.rstrip("\n") + ("\n\n" if original else "") + block + "\n"

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(path, "w").write(new_content)


def build_profile_stanza(account_id, account_name, role, prefix, session_name, region):
    name = profile_name(account_name, role, account_id, prefix)
    lines = [f"[profile {name}]"]
    if session_name:
        lines.append(f"sso_session = {session_name}")
    lines.append(f"sso_account_id = {account_id}")
    lines.append(f"sso_role_name = {role}")
    if region:
        lines.append(f"region = {region}")
    return "\n".join(lines)


def cmd_generate_profiles(args):
    token, sso = make_sso_client(args.session, args.region)

    stanzas = []
    for account_id, account_name, roles in iter_accounts_with_roles(token, sso):
        for role in roles:
            name = profile_name(account_name, role, account_id, args.prefix)
            print(f"  {name}  ({account_name} / {role} / {account_id})", file=sys.stderr)
            stanzas.append(
                build_profile_stanza(
                    account_id, account_name, role, args.prefix, args.session, args.region
                )
            )

    config_path = os.path.expanduser(os.environ.get("AWS_CONFIG_FILE", "~/.aws/config"))
    block_in_file(config_path, "\n\n".join(stanzas), block_id="aws-sso-managed")
    print(f"Wrote {len(stanzas)} profile(s) to {config_path}")


def iter_sso_profiles(session_filter=None, role_pattern=None):
    config_path = os.path.expanduser(os.environ.get("AWS_CONFIG_FILE", "~/.aws/config"))
    config = configparser.ConfigParser()
    config.read(config_path)
    for section in config.sections():
        if not section.startswith("profile "):
            continue
        profile = dict(config[section])
        if "sso_account_id" not in profile or "sso_role_name" not in profile:
            continue
        if session_filter and profile.get("sso_session") != session_filter:
            continue
        if role_pattern and not role_pattern.search(profile["sso_role_name"]):
            continue
        yield section[len("profile "):], profile


def iter_eks_clusters(account_id, role, token, sso, region):
    creds = sso.get_role_credentials(
        accountId=account_id, roleName=role, accessToken=token
    )["roleCredentials"]
    eks = boto3.client(
        "eks",
        region_name=region,
        aws_access_key_id=creds["accessKeyId"],
        aws_secret_access_key=creds["secretAccessKey"],
        aws_session_token=creds["sessionToken"],
    )
    for page in eks.get_paginator("list_clusters").paginate():
        yield from page["clusters"]


def cmd_generate_kubeconfig(args):
    role_pattern = re.compile(args.role_pattern)
    eks_region = args.eks_region or args.region or "us-east-1"
    prefix_filter = to_kebab(args.prefix) + "--" if args.prefix else None
    sso_cache = {}

    for aws_profile, profile in iter_sso_profiles(args.session, role_pattern):
        if prefix_filter and not aws_profile.startswith(prefix_filter):
            continue
        account_id = profile["sso_account_id"]
        role = profile["sso_role_name"]
        sso_session = profile.get("sso_session")

        if sso_session not in sso_cache:
            sso_cache[sso_session] = make_sso_client(sso_session, args.region)
        token, sso = sso_cache[sso_session]

        for cluster in iter_eks_clusters(account_id, role, token, sso, eks_region):
            short_alias = to_name(args.prefix, cluster)
            print(f"  {aws_profile}  ({role} / {cluster})", file=sys.stderr)
            subprocess.run(
                [
                    "aws", "eks", "update-kubeconfig",
                    "--name", cluster,
                    "--region", eks_region,
                    "--profile", aws_profile,
                    "--alias", aws_profile,
                ],
                check=True,
            )
            if short_alias != aws_profile:
                arn = f"arn:aws:eks:{eks_region}:{account_id}:cluster/{cluster}"
                subprocess.run(
                    [
                        "kubectl", "config", "set-context", short_alias,
                        "--cluster", arn,
                        "--user", arn,
                    ],
                    check=True,
                )


def main():
    parser = argparse.ArgumentParser(prog="aws-sso")
    parser.add_argument(
        "--region", default=None, help="SSO region (overrides sso-session config)"
    )
    parser.add_argument(
        "--session",
        default=None,
        help="SSO session name (from ~/.aws/config [sso-session ...])",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List all SSO accounts and their roles")

    p = sub.add_parser(
        "generate-profiles",
        help="Print AWS config profile stanzas for all accounts and roles",
    )
    p.add_argument(
        "--prefix", default=None, help="Optional prefix prepended to each profile name"
    )

    p = sub.add_parser(
        "generate-kubeconfig",
        help="Register EKS clusters matching roles into kubeconfig",
    )
    p.add_argument(
        "--prefix", default=None, help="Optional prefix prepended to each context alias"
    )
    p.add_argument(
        "--role-pattern", default=".*", help="Regex to filter IAM roles (default: all)"
    )
    p.add_argument(
        "--eks-region", default=None, help="AWS region to list EKS clusters in (defaults to --region)"
    )

    args = parser.parse_args()
    if args.command == "list":
        cmd_list(args)
    elif args.command == "generate-profiles":
        cmd_generate_profiles(args)
    elif args.command == "generate-kubeconfig":
        cmd_generate_kubeconfig(args)


if __name__ == "__main__":
    main()
