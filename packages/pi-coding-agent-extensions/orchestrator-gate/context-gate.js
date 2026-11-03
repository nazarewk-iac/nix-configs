/**
 * Context gate for pi-orchestrator's `delegate` tool.
 *
 * A prompt rule cannot prevent "send a 468 KB transcript to a 32k model", because the orchestrator
 * cannot know what a sub-agent will read later. So the check lives here, in code, where a call can
 * be refused.
 *
 * Two additions, both applied by a wrapper around the delegate tool:
 *   - `{action:"measure", path}` returns `{bytes, lines}` for a path, so the caller asks instead of
 *     guessing;
 *   - `inputBytes` on a dispatch is compared against the TARGET agent's model context. Over the
 *     safe fraction, the dispatch is refused with the aliases that would fit.
 *
 * The model context comes from the fleet's `/v1/models` (llama-swap publishes `context_length` per
 * alias), cached briefly. If the fleet is unreachable the gate degrades to "allow", so a network
 * problem never blocks work.
 */
import * as fs from "node:fs";

const SAFE_FRACTION = 0.75;   // leave a quarter of the window for the answer
const BYTES_PER_TOKEN = 4;    // rough, deliberately conservative
const CACHE_MS = 60_000;

let cache = { at: 0, models: null };

function fleetBase() {
	return process.env.KDN_LLM_BASE_URL || "https://brys.priv.nb.net.int.kdn.im/v1";
}

function apiKey() {
	try {
		const p = process.env.KDN_LLM_API_KEY_FILE || "/run/configs/llms/llama-server/api-keys/default";
		return fs.readFileSync(p, "utf8").trim();
	} catch {
		return process.env.KDN_LLM_API_KEY_brys || "";
	}
}

/** alias -> served context length. `null` means "could not ask the fleet". */
export async function aliasContexts() {
	if (cache.models && Date.now() - cache.at < CACHE_MS) return cache.models;
	try {
		const res = await fetch(`${fleetBase()}/models`, {
			headers: { Authorization: `Bearer ${apiKey()}` },
			signal: AbortSignal.timeout(3000),
		});
		if (!res.ok) return null;
		const body = await res.json();
		const models = new Map();
		const byAlias = [];
		for (const m of body.data ?? []) {
			if (typeof m.context_length === "number") {
				models.set(m.id, m.context_length);
				byAlias.push({ alias: m.id, context: m.context_length });
			}
		}
		const out = { byAlias: models, list: byAlias };
		cache = { at: Date.now(), models: out };
		return out;
	} catch {
		return null;
	}
}

export function measureFile(path) {
	const st = fs.statSync(path);
	if (!st.isFile()) return null;
	let lines = 0;
	const buf = fs.readFileSync(path);
	for (let i = 0; i < buf.length; i++) if (buf[i] === 10) lines++;
	return { bytes: st.size, lines };
}

/**
 * Decide whether `inputBytes` fits the model an agent will run on.
 *
 * Returns `{ ok: true }` or `{ ok: false, reason, fitting }`. A fleet that cannot be reached
 * returns `ok: true` with `assumed: true`, so a network fault never blocks a delegation.
 */
export async function checkInput(agentModel, inputBytes) {
	if (!inputBytes || inputBytes <= 0) return { ok: true };
	const ctx = await aliasContexts();
	if (!ctx) return { ok: true, assumed: true };

	const alias = (agentModel || "").replace(/^brys\//, "");
	const modelCtx = ctx.byAlias.get(alias);
	if (!modelCtx) return { ok: true, assumed: true };

	const tokens = Math.ceil(inputBytes / BYTES_PER_TOKEN);
	const budget = Math.floor(modelCtx * SAFE_FRACTION);
	if (tokens <= budget) return { ok: true, context: modelCtx, tokens };

	const fitting = ctx.list
		.filter((e) => Math.ceil(inputBytes / BYTES_PER_TOKEN) <= Math.floor(e.context * SAFE_FRACTION))
		.sort((a, b) => a.context - b.context)
		.map((e) => `${e.alias} (${e.context})`);

	return {
		ok: false,
		reason:
			`input is ~${tokens} tokens (${inputBytes} bytes at ${BYTES_PER_TOKEN} B/token), but ` +
			`${alias} serves ${modelCtx} tokens, and the safe budget is ${budget}.`,
		fitting: fitting.length ? fitting : ["(no local model is large enough — reduce the input first)"],
	};
}
