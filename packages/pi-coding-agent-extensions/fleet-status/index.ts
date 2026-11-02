/**
 * Fleet status, as a companion extension to pi-orchestrator.
 *
 * The orchestrator picks a model by intent, but intent alone cannot say whether a switch is
 * affordable or whether the host has headroom. This registers one read-only tool, `fleet-status`,
 * that answers both from the live llama-swap endpoints:
 *
 *   GET /v1/models   every alias with `context_length` and `status.value` (loaded | unloaded)
 *   GET /metrics     host RAM, VRAM, load average, swap — the headroom families
 *
 * Why these two and not /running: `/v1/models` already publishes the loaded state per alias, so
 * loaded-ness and context come from ONE call (the research file assumed `/running` was needed and
 * that loaded ids were base ids needing a join — `/v1/models` gives the alias directly). `/running`
 * still reports base ids only, so it is not used.
 *
 * Degradation is the rule, not an error path: when either call fails the tool returns the STATIC
 * view (aliases and context, from the same source the catalog renders) with `stale: true`, so a
 * network fault never stops a delegation. Review caveat C5: three TLS GETs under load can fail;
 * the tool always answers.
 *
 * No secret is stored here: the bearer key is read at runtime from the same file the LLM client
 * uses, and the base URL comes from the environment (`data/llm.nix` renders it into the client).
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import * as fs from "node:fs";

const TIMEOUT_MS = 3000; // total budget is one call each; a slow fleet must not stall a session
const FLEET_BASE = process.env.KDN_LLM_BASE_URL || "https://brys.priv.nb.net.int.kdn.im";

function apiKey(): string {
	const p =
		process.env.KDN_LLM_API_KEY_FILE || "/run/configs/llms/llama-server/api-keys/default";
	try {
		return fs.readFileSync(p, "utf8").trim();
	} catch {
		return process.env.KDN_LLM_API_KEY_brys || "";
	}
}

async function getJson(path: string): Promise<any | null> {
	try {
		const res = await fetch(`${FLEET_BASE}${path}`, {
			headers: { Authorization: `Bearer ${apiKey()}` },
			signal: AbortSignal.timeout(TIMEOUT_MS),
		});
		if (!res.ok) return null;
		return await res.json();
	} catch {
		return null;
	}
}

async function getText(path: string): Promise<string | null> {
	try {
		const res = await fetch(`${FLEET_BASE}${path}`, {
			headers: { Authorization: `Bearer ${apiKey()}` },
			signal: AbortSignal.timeout(TIMEOUT_MS),
		});
		if (!res.ok) return null;
		return await res.text();
	} catch {
		return null;
	}
}

/** Parse the few `/metrics` families that describe headroom. Values are bytes unless noted. */
function parseMetrics(text: string) {
	const one = (family: string): number | null => {
		const re = new RegExp(`^${family}\\s+([0-9.eE+\\-]+)`, "m");
		const m = text.match(re);
		return m ? Number(m[1]) : null;
	};
	const labelled = (family: string, label: string): number | null => {
		const re = new RegExp(`^${family}\\{[^}]*${label}[^}]*\\}\\s+([0-9.eE+\\-]+)`, "m");
		const m = text.match(re);
		return m ? Number(m[1]) : null;
	};
	const gb = (b: number | null) => (b === null ? null : Math.round((b / 1024 ** 3) * 10) / 10);
	return {
		ram_used_gb: gb(one("llamaswap_memory_used_bytes")),
		ram_total_gb: gb(one("llamaswap_memory_total_bytes")),
		swap_used_gb: gb(one("llamaswap_swap_used_bytes")),
		swap_total_gb: gb(one("llamaswap_swap_total_bytes")),
		// The W6600 is GPU 0 on brys; sum every card for the aggregate VRAM picture.
		vram_used_gb: gb(sumFamily(text, "llamaswap_gpu_memory_used_bytes")),
		vram_total_gb: gb(sumFamily(text, "llamaswap_gpu_memory_total_bytes")),
		load1: labelled("llamaswap_load_average", 'interval="1m"'),
	};
}

/** Sum a labelled Prometheus family across every series line (all GPU cards). */
function sumFamily(text: string, family: string): number | null {
	const re = new RegExp(`^${family}\\{[^}]*\\}\\s+([0-9.eE+\\-]+)`, "gm");
	let total = 0;
	let seen = false;
	let m: RegExpExecArray | null;
	while ((m = re.exec(text)) !== null) {
		total += Number(m[1]);
		seen = true;
	}
	return seen ? total : null;
}

interface ModelRow {
	alias: string;
	model: string;
	context: number;
	loaded: boolean;
}

/** Build the alias rows from `/v1/models`. `loaded` comes from `status.value`. */
function modelRows(modelsJson: any): ModelRow[] {
	const rows: ModelRow[] = [];
	for (const m of modelsJson?.data ?? []) {
		if (typeof m.context_length !== "number") continue;
		rows.push({
			alias: m.id,
			model: m.meta?.llamaswap?.modelID ?? m.name ?? m.id,
			context: m.context_length,
			loaded: m.status?.value === "loaded",
		});
	}
	return rows.sort((a, b) => a.alias.localeCompare(b.alias));
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "fleet-status",
		label: "Fleet status",
		description:
			"Report the live state of the local model fleet: which aliases are loaded right now, " +
			"each alias' served context, and the host headroom (RAM, VRAM, load average, swap). " +
			"Call it before choosing a model that would force a cold load. It never throws: on a " +
			"network fault it returns the static view with `stale: true`.",
		parameters: Type.Object({}),
		async execute() {
			const [modelsJson, metricsText] = await Promise.all([
				getJson("/v1/models"),
				getText("/metrics"),
			]);

			const stale = modelsJson === null;
			const models = modelsJson ? modelRows(modelsJson) : [];
			const resources = metricsText ? parseMetrics(metricsText) : null;

			const loaded = models.filter((m) => m.loaded).map((m) => m.alias);
			const out = {
				stale,
				loaded,
				resources,
				models: models.map((m) => ({
					alias: m.alias,
					model: m.model,
					context: m.context,
					loaded: m.loaded,
				})),
				note: stale
					? "fleet unreachable; static view only. Do not assume anything is loaded."
					: resources === null
						? "/metrics unreachable; loaded state is live but headroom is unknown."
						: undefined,
			};
			return { content: [{ type: "text", text: JSON.stringify(out, null, 1) }] };
		},
	});
}
