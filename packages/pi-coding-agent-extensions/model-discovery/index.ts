/**
 * Model discovery for the local LLM fleet, as a Pi provider extension.
 *
 * Pi builds its model catalog from static `models.json` (data/llm.nix). That
 * catalog cannot see two things that change on their own:
 *
 *   - llama-swap's real served set and per-model context (`/v1/models` on the
 *     router, alias-keyed, with `context_length`), and
 *   - the LiteLLM gateway's live groups, including the Requesty SaaS ids, which
 *     are discovered on the server and cannot be listed in Nix.
 *
 * This extension registers dynamic providers with `refreshModels`, so
 * `pi --list-models` and `/model` show the LIVE catalog. Static `models.json`
 * still layers over them (Pi composes `models.json` above a registered native
 * provider), so curated aliases keep their names and overrides.
 *
 * A live catalog does not carry every field: an OpenAI-compatible `/v1/models`
 * response has no standard for input modalities, and a gateway may omit a token
 * budget. `catalog.json`, generated from `lib/llm.nix` at build time, is the
 * same client projection as `models.json`; a discovered entry inherits the
 * curated `input`, context and output cap when the endpoint does not publish
 * them. That is why `vision-*` aliases show image input even though LiteLLM
 * advertises no modality field.
 *
 * Requesty's `/v1/models` lists provider-scoped ids (`deepinfra/<model>`) plus
 * the `model_canonical_name` that routes across them. The canonical name is an
 * aggregate alias (`deepseek-v4.1-flash-1017`), so this extension synthesizes
 * one entry per canonical name and unions its providers' capabilities.
 *
 * Degrade, never fail: a network fault keeps the previous list (or an empty one)
 * and never aborts startup. The token is read at request time from the same sops
 * files the clients use.
 */
import type { ExtensionAPI, ProviderModelConfig } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";

const TIMEOUT_MS = 4000;

const DEFAULT_CONTEXT = 32768;
const DEFAULT_MAX_TOKENS = 4096;

type KeySource = { file: string; jsonPath?: string[] };

type Endpoint = {
  id: string;
  name: string;
  baseUrl: string;
  /** Pi `!command` form, resolved per request. */
  keyCommand: string;
  /** Sources for the discovery GET, tried in order. */
  keySources: KeySource[];
  apiKeyEnv?: string;
  /** Force the openai-completions API (llama-swap never advertises it). */
  api: "openai-completions";
  /** Static `models.json` providers whose curated fields fill live gaps. */
  staticProviders: string[];
  /** A live field whose value is an aggregate alias across providers. */
  aggregateField?: string;
};

type StaticModel = {
  id: string;
  /** The served model id behind an alias (lib/llm.nix `piEntries`). */
  baseId?: string;
  input?: string[];
  contextWindow?: number;
  maxTokens?: number;
  reasoning?: boolean;
  thinkingLevelMap?: Record<string, string>;
};

function readKey(sources: KeySource[], fallbackEnv?: string): () => string {
  return () => {
    for (const source of sources) {
      try {
        let value = fs.readFileSync(source.file, "utf8").trim();
        if (source.jsonPath) {
          let node: unknown = JSON.parse(value);
          for (const part of source.jsonPath) node = (node as Record<string, unknown>)?.[part];
          value = typeof node === "string" ? node.trim() : "";
        }
        if (value) return value;
      } catch {
        // Try the next source.
      }
    }
    return fallbackEnv ? (process.env[fallbackEnv] ?? "") : "";
  };
}

const REQUESTY_KEY_SOURCES: KeySource[] = [
  { file: "/run/configs/llms/requesty/api-key" },
  { file: `${process.env.HOME ?? ""}/.local/share/opencode/auth.json`, jsonPath: ["requesty", "key"] },
];

const REQUESTY_KEY_COMMAND =
  "!cat /run/configs/llms/requesty/api-key 2>/dev/null || jq -r '.requesty.key // empty' \"$HOME/.local/share/opencode/auth.json\"";

function endpoints(): Endpoint[] {
  const out: Endpoint[] = [];
  const litellm = process.env.KDN_PI_DISCOVER_LITELLM || "https://litellm.etra.priv.nb.net.int.kdn.im/v1";
  const litellmKey = process.env.KDN_PI_DISCOVER_LITELLM_KEY || "/run/configs/llms/litellm/client-key";
  const llama = process.env.KDN_PI_DISCOVER_LLAMASWAP || "http://127.0.0.1:9530/v1";
  const llamaKey =
    process.env.KDN_PI_DISCOVER_LLAMASWAP_KEY || "/run/configs/llms/llama-server/api-keys/default";

  if (process.env.KDN_PI_DISCOVER_NO_LITELLM !== "1") {
    out.push({
      id: "litellm-dynamic",
      name: "LiteLLM (discovered)",
      baseUrl: litellm,
      keyCommand: "!cat " + litellmKey,
      keySources: [{ file: litellmKey }],
      apiKeyEnv: "KDN_LLM_API_KEY_litellm",
      api: "openai-completions",
      // The gateway front-ends local aliases and the Requesty deployments, so both
      // static providers supply the curated capability fields.
      staticProviders: ["litellm", "requesty"],
    });
  }
  if (process.env.KDN_PI_DISCOVER_NO_LLAMASWAP !== "1") {
    out.push({
      id: "llamaswap-dynamic",
      name: "llama-swap (discovered)",
      baseUrl: llama,
      keyCommand: "!cat " + llamaKey,
      keySources: [{ file: llamaKey }],
      apiKeyEnv: "KDN_LLM_API_KEY_brys",
      api: "openai-completions",
      staticProviders: ["brys", "oams"],
    });
  }
  if (process.env.KDN_PI_DISCOVER_NO_REQUESTY !== "1") {
    out.push({
      id: "requesty-dynamic",
      name: "Requesty (discovered)",
      baseUrl: process.env.KDN_PI_DISCOVER_REQUESTY || "https://router.requesty.ai/v1",
      keyCommand: REQUESTY_KEY_COMMAND,
      keySources: REQUESTY_KEY_SOURCES,
      apiKeyEnv: "REQUESTY_API_KEY",
      api: "openai-completions",
      staticProviders: ["requesty"],
      // `deepinfra/deepseek-v4.1-flash-1017` and `runware/...` share a canonical
      // name that Requesty routes across both providers, so it is a real model id.
      aggregateField: "model_canonical_name",
    });
  }
  return out;
}

/** Static client catalog generated from lib/llm.nix, keyed by provider. */
let catalogCache: Record<string, StaticModel[]> | null = null;

function catalog(): Record<string, StaticModel[]> {
  if (catalogCache) return catalogCache;
  catalogCache = {};
  try {
    const url = new URL("./catalog.json", import.meta.url);
    // `mkPiModelsJson` returns the provider map directly; a Pi `models.json` wraps
    // it in `providers`. Accept both so the same generated file works either way.
    const parsed = JSON.parse(fs.readFileSync(url, "utf8")) as {
      providers?: Record<string, { models?: StaticModel[] }>;
    } & Record<string, { models?: StaticModel[] }>;
    const providers = parsed.providers ?? parsed;
    for (const [provider, config] of Object.entries(providers)) {
      catalogCache[provider] = Array.isArray(config?.models) ? config.models : [];
    }
  } catch {
    // No bundled catalog: discovery still works from live metadata alone.
  }
  return catalogCache;
}

/**
 * Match a live id against the curated catalog. Gateway ids add provider prefixes
 * (`requesty/deepinfra/<model>`) and tier suffixes (`<model>:priority`), so the
 * segment match falls back from exact to basename to basename without the tier.
 * Only the endpoint's own static providers are searched, so a local model that
 * shares a name with a cloud one cannot give the cloud entry the wrong fields.
 */
function staticFor(ep: Endpoint, id: string): StaticModel | undefined {
  // A gateway id that names the Requesty provider is a cloud route, not the local
  // fleet: only requesty's curated entries describe it, even when a local model
  // happens to share the basename.
  const providers = id.startsWith("requesty/") ? ["requesty"] : ep.staticProviders;
  const models = providers.flatMap((provider) => catalog()[provider] ?? []);
  const exact = models.find((model) => model.id === id);
  if (exact) return exact;
  const basename = id.split("/").pop() ?? id;
  const byName = models.find((model) => model.id === basename);
  if (byName) return byName;
  const withoutTier = basename.replace(/:[a-z0-9_-]+$/i, "");
  const byTierlessName = models.find((model) => model.id === withoutTier);
  if (byTierlessName) return byTierlessName;
  // A gateway prefixes a remote id with its provider (`requesty/deepinfra/<model>`),
  // so the alias entry is reachable only through the served model id it carries.
  return models.find((model) => model.baseId === withoutTier);
}

function positive(value: unknown): number | null {
  return Number(value) > 0 ? Number(value) : null;
}

async function getModels(baseUrl: string, key: string, signal: AbortSignal): Promise<any[]> {
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/models`, {
    headers: key ? { Authorization: `Bearer ${key}` } : {},
    signal,
  });
  if (!res.ok) throw new Error(`GET ${baseUrl}/models -> ${res.status}`);
  const body = (await res.json()) as { data?: any[] };
  return Array.isArray(body.data) ? body.data : [];
}

/** Add one entry per aggregate alias, with the union of its providers' fields. */
function withAggregates(ep: Endpoint, list: any[]): any[] {
  if (!ep.aggregateField) return list;
  const ids = new Set(list.map((model) => String(model.id)));
  const aggregates = new Map<string, any>();
  for (const model of list) {
    const name = String(model[ep.aggregateField] ?? "").trim();
    if (!name || ids.has(name)) continue;
    const entry = aggregates.get(name) ?? { id: name, name, api: model.api };
    entry.context_window = Math.max(positive(entry.context_window) ?? 0, positive(model.context_window) ?? 0);
    entry.max_output_tokens = Math.max(
      positive(entry.max_output_tokens) ?? 0,
      positive(model.max_output_tokens) ?? 0,
    );
    entry.supports_vision = entry.supports_vision === true || model.supports_vision === true;
    aggregates.set(name, entry);
  }
  return [...list, ...aggregates.values()];
}

function toConfig(ep: Endpoint, m: any): ProviderModelConfig {
  const id = String(m.id);
  const name = typeof m.name === "string" && m.name.trim() ? m.name : id;
  const curated = staticFor(ep, id);

  // The curated client budget wins for the output cap: a provider's advertised
  // `max_output_tokens` is often a hard maximum (384K for DS4.1 on runware) that
  // is a poor default request budget. Context prefers the gateway: a host may
  // serve an alias below the native window.
  const advertisedIn =
    positive(m.max_input_tokens) ?? positive(m.context_length) ?? positive(m.context_window);
  const ctx = advertisedIn ?? curated?.contextWindow ?? DEFAULT_CONTEXT;
  const advertisedOut = positive(m.max_output_tokens);
  // An advertised output limit is a hard maximum, not a request budget: Requesty
  // reports 384K for DS4.1. Cap it at 32K, the same ceiling Pi applies near a
  // full window, so a normal request does not reserve the whole window.
  const maxTokens = curated?.maxTokens ?? Math.min(advertisedOut ?? DEFAULT_MAX_TOKENS, 32768);

  const input: string[] = Array.isArray(m.input)
    ? m.input.filter((value: any) => value === "text" || value === "image")
    : m.supports_vision === true
      ? ["text", "image"]
      : (curated?.input ?? ["text"]);

  const reasoning = curated?.reasoning ?? /thinking|reason|o1|o3|qwen3|deepseek-r/i.test(`${id} ${name}`);

  return {
    type: "chat",
    id,
    name,
    api: ep.api,
    baseUrl: ep.baseUrl,
    reasoning,
    ...(curated?.thinkingLevelMap ? { thinkingLevelMap: curated.thinkingLevelMap } : {}),
    input,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: ctx,
    maxTokens: Math.min(maxTokens, ctx),
  };
}

function register(pi: ExtensionAPI, ep: Endpoint): void {
  // Legacy ProviderConfig form: `refreshModels` returns the live model list and Pi
  // replaces this registration's live models with it. No persistence: the catalog
  // is live, so a stale snapshot would be worse than a fetch on next start.
  pi.registerProvider(ep.id, {
    name: ep.name,
    baseUrl: ep.baseUrl,
    // A `!command` apiKey so discovered models authenticate at inference, not
    // only the catalog GET (an empty key 401s on call). Pi resolves it per request.
    apiKey: ep.keyCommand,
    api: ep.api,
    authHeader: true,
    models: [],
    refreshModels: async (context) => {
      // `pi --list-models` runs offline-safe (allowNetwork=false) and still calls
      // this. Attempt the fetch (short timeout, degrades to []), unless explicitly
      // opted out with KDN_PI_DISCOVER_OFFLINE=1.
      if (process.env.KDN_PI_DISCOVER_OFFLINE === "1") return [];
      const signal = context.signal ?? AbortSignal.timeout(TIMEOUT_MS);
      try {
        const key = readKey(ep.keySources, ep.apiKeyEnv)();
        const list = await getModels(ep.baseUrl, key, signal);
        return withAggregates(ep, list).map((model) => toConfig(ep, model));
      } catch {
        // Degrade: keep whatever Pi already has (empty on first failure).
        return [];
      }
    },
  });
}

export default function (pi: ExtensionAPI): void {
  for (const ep of endpoints()) register(pi, ep);
}
