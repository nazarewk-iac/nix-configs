---
type: Reference
description: Standalone NixOS slot serving local LLMs via llama-server router mode behind a self-signed-certificate Caddy reverse proxy, with a server-side OpenCode DSML compat-proxy. Consumers (brys, oams) talk to the HTTPS endpoint over the LAN via a thin opencode devenv profile.
timestamp: 2026-08-31T00:00:00+02:00
---

# kdn.llm.local — local LLM serving

A standalone NixOS slot that serves several local LLMs with a single
llama-server (from llama.cpp) running in **router mode**: it owns one
OpenAI-compatible HTTP API on loopback, loading/unloading individual GGUFs on
demand. Exactly **one** model is resident in RAM at a time (`--models-max 1`);
the others stay on disk.

A self-signed-certificate **Caddy** reverse proxy exposes the endpoint on the
LAN (`brys.lan.etra.net.int.kdn.im`, TCP 80/443 only). Between Caddy and the
loopback server sits one OpenCode DSML compat-proxy instance that both
translates DeepSeek DSML / Qwen XML tool calls and passes every other path
through — so a single instance correctly fronts a server that does its own
model routing.

Consumers talk to the HTTPS endpoint over the LAN. The self-signed cert and the
shared API key are mounted at `/run/configs/llms` on the consuming hosts (brys,
oams); each consumer wires opencode to it via a thin hostname-scoped `kdn.opencode`
devenv profile (see `hosts/oams/devenv.nix`).

Currently applied to the **brys** host (`hosts/brys/default.nix`). See
[`docs/local-llms.md`](../../../docs/local-llms.md) for a deployment example
and the exact brys state.

## Characteristics

- **Standalone.** This slot uses only `lib`, `pkgs`, `config`, and plain NixOS
  options. It never references or assigns a `modules/universal/`- or
  `modules/meta/`-declared option (no `kdn.env.*`, `kdn.disks.*`, `kdnConfig`).
  See [Slots Standalone](../../../.agents/rules/slots-standalone.md).
- **One model at a time.** The router loads the requested model into RAM and
  unloads it when you ask for a different one. Loaded models stay resident once
  loaded (the router caches them), so slow-to-load frontier models don't churn.
- **Loopback-only back end.** llama-server and the compat-proxy bind
  `127.0.0.1`. Only Caddy listens on the network (80/443, hard-coded,
  non-configurable).
- **API-key protected.** llama-server is started with `--api-key-file` (a
  host-wired path); the compat-proxy forwards the client's Bearer header so the
  key reaches llama-server.
- **Sequential downloads.** A single download service walks all enabled models
  one at a time in the host network namespace, with HF transfer concurrency
  capped by `download.mode` (slow / fast-polite).

## How to enable

In a NixOS host (`hosts/<name>/default.nix`), inside the existing `mkSlots`
block:

```nix
slots = kdnConfig.self.mkSlots {
  inherit pkgs;
  # ...existing slot enables...

  kdn.llm.local.enable = true;
  kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models"; # required, no default

  # LAN endpoint (required): the Caddy vhost hostname + its self-signed cert.
  kdn.llm.local.domain = "brys.lan.etra.net.int.kdn.im";
  kdn.llm.local.certs.certFile = "/run/configs/llms/certs/public.key";
  kdn.llm.local.certs.keyFile = "/run/configs/llms/certs/private.key";
  kdn.llm.local.apiKeyDir = "/run/configs/llms/llama-server/api-keys"; # optional

  kdn.llm.local.compatProxy.enable = true;    # default true
  kdn.llm.local.compatProxy.port = 9530;       # loopback, between Caddy and server

  kdn.llm.local.download.mode = "slow";        # global (default "slow" | "fast-polite")

  kdn.llm.local.models = {
    qwen3-30b-a3b = {
      enable = true;
      hfRepo = "Qwen/Qwen3-30B-A3B-GGUF";
      hfFile = "Qwen3-30B-A3B-Q4_K_M.gguf";
      aliases = [ "fast" ];
    };
    # ...more models...
  };
};
```

`modelsDir`, `domain`, and the two cert paths have no defaults and must be
supplied by the host. The host may also register `modelsDir` in its own
persistence machinery (for example `kdn.disks.persist...`). The slot does not
create or own any specific mountpoint.

### Certificates

The self-signed certificate is **generated once, outside the module system**,
and stored as a secret. There is no cert-generation logic anywhere in the
module tree — the slot only reads the decrypted files. To (re)generate:

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -nodes -keyout private.key -out public.key -days 3650 \
  -subj "/CN=brys.lan.etra.net.int.kdn.im" \
  -addext "subjectAltName=DNS:brys.lan.etra.net.int.kdn.im"
```

...then encrypt both files (and the API key) into `llms.nonsensitive.sops.yaml`
under `brys/` so they decrypt to the paths the host wired above.

## Serving

Topology (all but Caddy on loopback):

```
LAN client ──HTTPS──▶ Caddy (:80/:443) ──▶ compat-proxy (:9530) ──▶ llama-server (:39703, --api-key-file)
```

- `kdn.llm.local.server.host` / `server.port` (defaults `127.0.0.1`/`39703`)
  set the router llama-server bind address. Keep `server.host` on loopback.
- `kdn.llm.local.domain` is the Caddy vhost hostname. Caddy terminates TLS with
  `certs.certFile`/`certs.keyFile` and reverse-proxies to the loopback
  compat-proxy. Firewall `allowedTCPPorts` is **hard-coded** to `[80 443]` and
  not configurable.
- `kdn.llm.local.compatProxy.enable` (default `true`) puts the DSML compat-proxy
  in the path. Disable it to talk straight to llama-server over Caddy (you'd
  lose DSML translation). `compatProxy.port` is loopback.
- `apiKeyDir` (optional) is a **directory of single-key files** (one key per
  file). A llama-cpp `preStart` assembles every file under it — stripping `#`
  comment lines and empty lines — into `/var/lib/llama-cpp/api-keys`, and
  llama-server reads that assembled file via `--api-key-file`. When set, clients
  must send `Authorization: Bearer <key>`; the compat-proxy forwards it on both
  streaming and non-streaming paths (`forwardClientAuth`).
- Send requests to `/v1/chat/completions` on the domain. Set the `model` field
  to a model name or alias. The router loads or swaps the model automatically.

## Downloading models

A single `systemd` service `kdn-llm-download` downloads the GGUF of every
**enabled** model with the `hf` CLI into `<modelsDir>/<hfRepo>/<hfFile>`,
**one model at a time, sequentially** (never concurrently). After each
download it logs a status line (size + path). It skips models whose file
already exists (unless `download.force`).

Downloads run directly in the host network namespace; `download.mode` controls
how aggressively HF transfers (env-based concurrency capping — the Xet Tier 1
mitigation set).

Global download options (`kdn.llm.local.download.*`):

- `download.mode` (default `"slow"`) — `"slow"` or `"fast-polite"`. Applied to
  **all** models.
  - `"slow"` (default): disable Xet high-performance transfer
    (`HF_XET_HIGH_PERFORMANCE=false`, `HF_HUB_DISABLE_XET=true`). Falls back
    to regular HTTP transfer, gentlest on a shared link.
  - `"fast-polite"`: keep Xet enabled but pin concurrency low (disable
    adaptive ramping, fixed low concurrency). Faster than `"slow"`, far
    gentler than Xet's full `"fast"`. This is the Tier 1 XET mitigation.
- `download.xetConcurrency` (default `2`) — Xet download concurrency used in
  `"fast-polite"` mode.
- `download.tokenFile` (default `null`) — path to a file with a HuggingFace
  token, loaded via systemd `LoadCredential`. The host wires this (e.g. via
  sops-nix to `/run/configs/llms/huggingface/token`).

## Per-model options

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `false` | serve this model in the router server |
| `hfRepo` | string | required | HuggingFace repo `owner/name` |
| `hfFile` | string | required | GGUF path within `hfRepo`; may be a subdir path or the first shard of a split |
| `download.glob` | string or null | `null` | glob within `hfRepo` the download fetches (e.g. all shards of a split); when set the download always runs |
| `download.minBytes` | int or null | `null` | minimum acceptable size in bytes for `hfFile`; a smaller existing file is treated as a stub — both it and its HF etag metadata are deleted and it is re-downloaded. Use on split models so an interrupted first shard is repaired. |
| `download.enable` | bool | `true` | include in the sequential download run |
| `download.force` | bool | `false` | re-download even if present |
| `aliases` | list of string | `[]` | extra names the router server answers to |
| `perf.threads` | int or null | `null` | `llama-server -t`; null uses the slot default `16` |
| `perf.flashAttention` | `on`/`off`/`auto` | `on` | `--flash-attn` |
| `perf.contextSize` | int or null | `null` | `--ctx-size` (KV-cache RAM budget); null uses the model default |
| `perf.mmap` | bool | `true` | memory-map the model file |
| `perf.parallel` | int | `1` | `--parallel` server slots (1 wastes no KV cache) |
| `perf.reasoning` | `on`/`off`/`auto` | `off` | `--reasoning`; off skips invisible thinking so short queries stream immediately |
| `perf.specType` | string | `draft-dspark` | `--spec-type` used when `draft.enable` is set |
| `draft.enable` | bool | `false` | download and use a speculative-decoding draft model for this model |
| `draft.hfRepo` | string | `""` | HuggingFace repo of the draft GGUF |
| `draft.hfFile` | string | `""` | GGUF file name of the draft within `draft.hfRepo` |

The draft model is fetched by `kdn-llm-download` **before** the parent model
(so it is ready when the router loads the parent), but it is *not* registered
as a router model — it only feeds `model-draft`/`spec-type` on the parent's
preset section.

Router-mode note: the router generates the `--models-preset` INI from these
options at build time — each enabled model becomes a `[<name>]` section with
`model = <abs path>` plus optional `alias`/`threads`. The section name (the
slot's model attr name) is the model id the API answers to, so client configs
keyed on friendly names (`deepseek-v4-flash`, `frontier`, ...) keep working.

There is no per-model `ttl` in router mode; the router keeps a loaded model
resident once loaded. Set `--models-max` implicitly to `1` (exactly one model
resident). The slot hard-codes `models-max=1` to preserve the "one model at a
time" behaviour; it is not configurable.

Only `enable = true` models are configured and downloaded. Keep the other
models declared-but-disabled to add them later with a one-line change.

## Consuming from a LAN host (`kdn.llm.client`)

The endpoint is consumed over HTTPS with the shared `/run/configs/llms` mount
(the self-signed cert and the API key). A **client slot**
(`modules/slots/llm/client/`) adds an opencode provider per configured
upstream; it does **not** enable opencode itself and ships **no** per-upstream
wrapper. Each upstream is keyed by name (`upstreams.<name>` →
`provider.<name>`). The consumer's devenv enables `kdn.opencode` (turns
opencode on and provides the single `opencode-kdn` wrapper, with the API key
injected via `wrapper.envFiles`), trusts the self-signed cert system-wide via
`security.pki`, and enables `kdn.llm.client` as a thin passthrough (see
`hosts/oams/devenv.nix`):

```nix
kdn.opencode.enable = true;                 # turns opencode on + default permission
kdn.opencode.wrapper.envFiles.KDN_LLM_API_KEY_brys = "/run/configs/llms/llama-server/api-keys/default";
kdn.llm.client.enable = true;
kdn.llm.client.upstreams.brys = {
  enable = true;
  baseURL = "https://brys.priv.nb.net.int.kdn.im/v1";
  models = { "deepseek-v4-flash" = { ... }; };
};
# ... add more upstreams as upstreams.<other> = { ... };
```

For the `brys` upstream, the slot adds an `@ai-sdk/openai-compatible`
`provider.brys` bound to `baseURL` with `apiKey = {env:KDN_LLM_API_KEY_brys}`.
The single `opencode-kdn` wrapper loads that key from the `envFiles` path you
set; run opencode via `opencode-kdn` inside the devenv shell.

## Operations

- **Status:** `kdn-llm-status` (installed into PATH) shows the router
  llama-server, the loopback compat-proxy, Caddy, the download service, and
  recent download logs.
- **Run a download:** `systemctl start kdn-llm-download` (or the
  `kdn-llm-download.target`).
- **Watch a download:** `journalctl -fu kdn-llm-download`.

## Notes for a CPU-only 128 GB machine (brys)

- Prefer MoE models; they activate a fraction of their parameters and are far
  more RAM-bandwidth efficient on DDR4.
- A ~103 GB model loads in several minutes (disk + DDR4 bandwidth bound). A
  ~18 GB model loads in under a minute.
- First request to a loaded model may appear to hang while it loads — that is
  normal.
