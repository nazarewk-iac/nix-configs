#!/usr/bin/env python3
"""Discover Requesty's model catalogue into LiteLLM deployments.

Requesty is OpenAI-compatible but not a first-class LiteLLM provider, and a
`model_name: "requesty/*"` wildcard does NOT route (404) and fakes ~hundreds of
OpenAI price-map names into `/v1/models`. So the gateway needs EXPLICIT
deployments. This script produces them from Requesty's real `/v1/models`.

Two modes:
  * print:  emit a JSON *list* of deployment dicts (for inspection / Nix).
  * merge:  load a base LiteLLM config JSON, replace any existing `requesty/…`
            deployments with freshly discovered ones, write the result.

`--api-base` becomes the deployment's `api_base`; when the gateway reaches
Requesty with correct TLS/Host (e.g. via egress NAT) pass
`https://router.requesty.ai/v1`. `urllib` honours `HTTPS_PROXY`, so it also
works behind a CONNECT proxy (the proxy preserves SNI/Host).

Env:
  REQUESTY_API_KEY            (required)
  LITELLM_REQUESTY_PREFIX     default "requesty/"
"""

import argparse
import json
import os
import sys
import urllib.request


def _v1(api_base: str) -> str:
    base = api_base.rstrip("/")
    return base if base.endswith("/v1") else base + "/v1"


def fetch_ids(api_base: str, api_key: str) -> list[str]:
    url = _v1(api_base) + "/models"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}"})
    with urllib.request.urlopen(req, timeout=20) as resp:  # noqa: S310 (trusted, internal use)
        data = json.load(resp)
    return [
        m["id"] for m in data.get("data", []) if isinstance(m, dict) and m.get("id")
    ]


def make_deployments(ids: list[str], api_base: str, prefix: str) -> list[dict]:
    base = _v1(api_base)
    out = []
    for mid in sorted(set(ids)):
        if not mid:
            continue
        out.append(
            {
                "model_name": prefix + mid,
                "litellm_params": {
                    "model": "openai/" + mid,
                    "api_base": base,
                    "api_key": "os.environ/REQUESTY_API_KEY",
                },
                "model_info": {
                    "id": "requesty-" + mid.replace("/", "-").replace(":", "_")
                },
            }
        )
    return out


def merge(base_cfg: dict, new_deployments: list[dict], prefix: str) -> dict:
    kept = [
        m
        for m in base_cfg.get("model_list", [])
        if not str(m.get("model_name", "")).startswith(prefix)
    ]
    base_cfg["model_list"] = kept + new_deployments
    return base_cfg


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--api-base",
        default=os.environ.get("REQUESTY_EGRESS", "https://router.requesty.ai"),
    )
    ap.add_argument(
        "--prefix", default=os.environ.get("LITELLM_REQUESTY_PREFIX", "requesty/")
    )
    ap.add_argument("--base", help="base LiteLLM config JSON to merge into")
    ap.add_argument("--out", help="write merged config here (implies --base)")
    args = ap.parse_args()

    api_key = os.environ.get("REQUESTY_API_KEY")
    if not api_key:
        print("REQUESTY_API_KEY is not set", file=sys.stderr)
        return 2

    try:
        ids = fetch_ids(args.api_base, api_key)
    except (
        Exception
    ) as exc:  # keep the gateway alive: report and let the caller fall back
        print(f"requesty discovery failed: {exc}", file=sys.stderr)
        return 1

    deployments = make_deployments(ids, args.api_base, args.prefix)

    if args.base and args.out:
        with open(args.base, encoding="utf-8") as fh:
            cfg = json.load(fh)
        cfg = merge(cfg, deployments, args.prefix)
        tmp = args.out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
        os.replace(tmp, args.out)
        print(
            f"merged {len(deployments)} requesty deployments into {args.out}",
            file=sys.stderr,
        )
    else:
        json.dump(deployments, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
