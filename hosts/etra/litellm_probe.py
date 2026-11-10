"""Host-side reachability filter for the LiteLLM gateway.

Loaded by LiteLLM as a callback (`probe.host_probe`) from beside config.yaml.
`async_filter_deployments` drops a deployment whose HOST is currently unreachable.

Why a file and not a probe here: this runs INSIDE the LiteLLM container, which
reaches each host only through the etra-side socat relay. The relay ACCEPTS the
TCP connect and then hangs on its upstream when the host is blackholed — so a
probe from here cannot tell "dead" from "slow". A tiny prober on the etra HOST
connects to each host's NetBird address directly (a real connect timeout) and
writes `/var/lib/litellm/host-health.json`, bind-mounted in here:
    {"brys": true, "oams": false}
Unknown host (missing key / unreadable file) means "assume healthy", so a prober
outage never starves routing.

Deployment -> host: the gateway ids every deployment `<host>-<alias>`
(`model_info.id`), so the host is the id prefix before the first dash.
"""

import json
import os

from litellm.integrations.custom_logger import CustomLogger


def host_of(deployment: dict) -> str:
    mid = (deployment.get("model_info") or {}).get("id", "")
    return mid.split("-", 1)[0] if "-" in mid else mid


class HostProbeFilter(CustomLogger):
    def __init__(self, path: str | None = None, **_ignored) -> None:
        super().__init__()
        self.path = path or os.environ.get(
            "KDN_HOST_HEALTH_FILE", "/var/lib/litellm/host-health.json"
        )

    def _health(self) -> dict:
        try:
            with open(self.path, encoding="utf-8") as fh:
                data = json.load(fh)
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    async def async_filter_deployments(
        self,
        model: str,
        healthy_deployments: list,
        messages=None,
        request_kwargs=None,
        parent_otel_span=None,
    ) -> list:
        # Never raise: a filter bug must not break routing. Any failure -> unfiltered.
        try:
            health = self._health()
            if not health:
                return healthy_deployments
            kept = [
                d
                for d in healthy_deployments
                if health.get(host_of(d), True) is not False
            ]
            # If every candidate is on a downed host, keep them all rather than
            # starve the group (matches LiteLLM's WhenAllUnhealthy=KeepAll).
            return kept or healthy_deployments
        except Exception:
            return healthy_deployments


# Module-level instance, so the config can name `probe.host_probe`.
host_probe = HostProbeFilter()
