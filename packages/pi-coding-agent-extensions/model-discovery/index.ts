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
 * This extension registers two dynamic providers with `refreshModels`, so
 * `pi --list-models` and `/model` show the LIVE catalog. Static `models.json`
 * still layers over them (Pi composes `models.json` above a registered native
 * provider), so curated aliases keep their names and overrides.
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

type Endpoint = {
  id: string;
  name: string;
  baseUrl: string;
  apiKey: () => string;
  /** Force the openai-completions API (llama-swap never advertises it). */
  api: "openai-completions";
};

function readKey(file: string, fallbackEnv?: string): () => string {
  return () => {
    try {
      return fs.readFileSync(file, "utf8").trim();
    } catch {
      return fallbackEnv ? (process.env[fallbackEnv] ?? "") : "";
    }
  };
}

function endpoints(): Endpoint[] {
  const out: Endpoint[] = [];
  const litellm = process.env.KDN_PI_DISCOVER_LITELLM || "https://litellm.etra.priv.nb.net.int.kdn.im/v1";
  const litellmKey = process.env.KDN_PI_DISCOVER_LITELLM_KEY || "/run/configs/llms/litellm/master-key";
  const llama = process.env.KDN_PI_DISCOVER_LLAMASWAP || "http://127.0.0.1:9530/v1";
  const llamaKey =
    process.env.KDN_PI_DISCOVER_LLAMASWAP_KEY || "/run/configs/llms/llama-server/api-keys/default";

  if (process.env.KDN_PI_DISCOVER_NO_LITELLM !== "1") {
    out.push({
      id: "litellm-dynamic",
      name: "LiteLLM (discovered)",
      baseUrl: litellm,
      api: "openai-completions",
      apiKey: readKey(litellmKey, "KDN_LLM_API_KEY_litellm"),
    });
  }
  if (process.env.KDN_PI_DISCOVER_NO_LLAMASWAP !== "1") {
    out.push({
      id: "llamaswap-dynamic",
      name: "llama-swap (discovered)",
      baseUrl: llama,
      api: "openai-completions",
      apiKey: readKey(llamaKey, "KDN_LLM_API_KEY_brys"),
    });
  }
  return out;
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

function toConfig(ep: Endpoint, m: any): ProviderModelConfig {
  const id = String(m.id);
  const name = typeof m.name === "string" && m.name.trim() ? m.name : id;
  const ctx =
    Number(m.context_length) > 0
      ? Number(m.context_length)
      : Number(m.contextWindow) > 0
        ? Number(m.contextWindow)
        : DEFAULT_CONTEXT;
  const reasoning = /thinking|reason|o1|o3|qwen3|deepseek-r/i.test(`${id} ${name}`);
  return {
    type: "chat",
    id,
    name,
    api: ep.api,
    baseUrl: ep.baseUrl,
    reasoning,
    input: Array.isArray(m.input) ? m.input.filter((x: any) => x === "text" || x === "image") : ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: ctx,
    maxTokens: Math.min(DEFAULT_MAX_TOKENS, ctx),
  };
}

function register(pi: ExtensionAPI, ep: Endpoint): void {
  // Legacy ProviderConfig form: `refreshModels` returns the live model list and Pi
  // replaces this registration's live models with it. No persistence: the catalog
  // is live, so a stale snapshot would be worse than a fetch on next start.
  pi.registerProvider(ep.id, {
    name: ep.name,
    baseUrl: ep.baseUrl,
    apiKey: "",
    api: ep.api,
    authHeader: true,
    models: [],
    refreshModels: async (context) => {
      // `pi --list-models` runs offline-safe (allowNetwork=false); still attempt the
      // fetch — it has its own short timeout and degrades to [] on failure.
      const signal = context.signal ?? AbortSignal.timeout(TIMEOUT_MS);
      try {
        const list = await getModels(ep.baseUrl, ep.apiKey(), signal);
        return list.map((m) => toConfig(ep, m));
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
