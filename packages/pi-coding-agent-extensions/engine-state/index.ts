/**
 * Engine state, injected into the prompt once per profile change.
 *
 * The brys engine serves one profile at a time. An alias such as `qfn` is `auto`: it resolves to
 * whichever profile is current, and a switch reloads the engine under the same name. A Pi session
 * caches the model entry it discovered at startup, so a running session cannot see the switch on
 * its own — there is no push channel (`refreshModels` runs at startup and on model refresh only).
 *
 * Two sources, in this order:
 *
 * 1. `GET /events/stream` — the manager's SSE feed. One connection per session, held open, with
 *    the journal's monotonic `seq` as the SSE id, so a reconnect resumes with `?since=`. This is
 *    the primary source: it reports a switch the moment it happens, including one that lands in
 *    the middle of a turn, which no poll can see.
 * 2. `GET /status` — the snapshot, used to seed the state before the stream connects and as the
 *    fallback whenever the stream is down. Cached for 30 s.
 *
 * `before_agent_start` then reads memory: zero network on a normal turn, and one injected line
 * only when the profile differs from what this session last told the model. A normal turn injects
 * nothing, so the prompt prefix stays stable and the cache is not invalidated per request.
 *
 * Degradation is the rule: no stream and no status means no line, never an error.
 *
 * Why not the proxy: the gateway can mutate a request (`pre_call`) or add a response field
 * (`post_call_success`), but it has no memory of what the client already knows, so it would either
 * inject on every request (tokens plus a cache miss each turn) or keep per-conversation state it
 * does not have. Pi ignores unknown response fields, so a response-level field reaches neither the
 * model nor the UI.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const STATUS_URL =
	process.env.KDN_ENGINE_STATUS_URL || "http://brys.priv.nb.net.int.kdn.im:8182/status";
const STREAM_URL = STATUS_URL.replace(/\/status$/, "") + "/events/stream";
const CACHE_MS = 30_000;
const TIMEOUT_MS = 1_500;
const RECONNECT_MS = 5_000;
// A stream that has said nothing for this long is treated as stalled, and the snapshot takes over.
const LIVE_STALE_MS = 10 * 60_000;

type Status = {
	profile?: string;
	in_flight?: number;
	last_switch_seconds_ago?: number;
};

let cached: { at: number; status: Status | null } = { at: 0, status: null };
/** The profile this session last told the model about. */
let lastProfile: string | null = null;
/** The newest state the stream has reported, or null while it has not reported anything. */
let live: Status | null = null;
/** When `live` was last known to be true. A stalled stream must not freeze the session's view. */
let liveAt = 0;
let lastSeq = 0;
let streamStarted = false;

async function readStatus(): Promise<Status | null> {
	const now = Date.now();
	if (now - cached.at < CACHE_MS) return cached.status;

	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
	try {
		const res = await fetch(STATUS_URL, { signal: controller.signal });
		if (!res.ok) throw new Error(String(res.status));
		const body = (await res.json()) as Status;
		cached = { at: now, status: body };
		return body;
	} catch {
		cached = { at: now, status: null };
		return null;
	} finally {
		clearTimeout(timer);
	}
}

/** One SSE block -> the fields this extension cares about. */
function applyEvent(data: string): void {
	let record: Record<string, unknown>;
	try {
		record = JSON.parse(data) as Record<string, unknown>;
	} catch {
		return;
	}
	const at = Date.now();
	if (record.event === "switch" && typeof record.to === "string") {
		live = {
			profile: record.to,
			last_switch_seconds_ago: 0,
			...(live?.in_flight !== undefined ? { in_flight: live.in_flight } : {}),
		};
		liveAt = at;
		return;
	}
	// A load or a stop does not change the profile, but it does refresh the clock the injected
	// line quotes, so keep the profile and reset the age.
	if (live && typeof record.event === "string" && record.event.startsWith("engine_")) {
		live = { ...live, last_switch_seconds_ago: 0 };
		liveAt = at;
	}
}

/**
 * Hold the feed open. Reconnects with `since=<last seq>` so a switch that happened while the
 * connection was down is still delivered exactly once. Never throws: a dead feed leaves `live` at
 * its last value and the poll takes over.
 */
async function holdStream(): Promise<void> {
	for (;;) {
		try {
			const res = await fetch(`${STREAM_URL}?since=${lastSeq}`, {
				headers: { Accept: "text/event-stream" },
			});
			if (!res.ok || !res.body) throw new Error(String(res.status));
			const reader = res.body.getReader();
			const decoder = new TextDecoder();
			let buffer = "";
			for (;;) {
				const { value, done } = await reader.read();
				if (done) break;
				buffer += decoder.decode(value, { stream: true });
				let split = buffer.indexOf("\n\n");
				while (split !== -1) {
					const block = buffer.slice(0, split);
					buffer = buffer.slice(split + 2);
					let data = "";
					for (const line of block.split("\n")) {
						if (line.startsWith("id:")) {
							const seq = Number(line.slice(3).trim());
							if (Number.isFinite(seq) && seq > lastSeq) lastSeq = seq;
						} else if (line.startsWith("data:")) {
							data += line.slice(5).trim();
						}
					}
					if (data) applyEvent(data);
					split = buffer.indexOf("\n\n");
				}
			}
		} catch {
			// fall through to the reconnect delay
		}
		await new Promise((resolve) => setTimeout(resolve, RECONNECT_MS));
	}
}

function line(status: Status): string {
	const switched =
		typeof status.last_switch_seconds_ago === "number"
			? `switched ${status.last_switch_seconds_ago}s ago`
			: "switch time unknown";
	return (
		`<engine profile="${status.profile}" in_flight="${status.in_flight ?? 0}" ${switched}/>\n` +
		"The model alias resolves to whichever profile is current, and a switch reloads the engine " +
		"once (~60 s). Its advertised window is the smallest text window, so it stays valid after " +
		"the switch."
	);
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async () => {
		// A restored session starts with no knowledge, so the first turn injects.
		lastProfile = null;
		if (streamStarted) return;
		streamStarted = true;
		// Seed from the snapshot, then let the feed keep it current.
		const seeded = await readStatus();
		if (seeded?.profile) {
			live = seeded;
			liveAt = Date.now();
		}
		void holdStream();
	});

	pi.on("before_agent_start", async (event, ctx) => {
		// The snapshot takes over when the feed has gone quiet: a stalled stream must not pin the
		// session to a profile it saw an hour ago.
		const stale = !live || Date.now() - liveAt > LIVE_STALE_MS;
		const status = stale ? await readStatus() : live;
		if (stale && status?.profile) {
			live = status;
			liveAt = Date.now();
		}
		const profile = status?.profile;
		if (!profile) return;
		try {
			ctx.ui.setStatus("engine", `engine: ${profile}`);
		} catch {
			// A non-TUI run has no status line; the prompt line is the contract.
		}
		if (profile === lastProfile) return; // unchanged: no prompt churn, no cache miss
		lastProfile = profile;
		return { systemPrompt: `${event.systemPrompt}\n\n${line(status)}` };
	});

	// `model_select` is a LOCAL change (`/model`, cycling, `pi.setModel()`); a profile switch on
	// the server does not fire it. Reuse it only to refresh the visible status.
	pi.on("model_select", async (_event, ctx) => {
		const status = live && Date.now() - liveAt <= LIVE_STALE_MS ? live : await readStatus();
		if (!status?.profile) return;
		try {
			ctx.ui.setStatus("engine", `engine: ${status.profile}`);
		} catch {
			// no TUI, nothing to update
		}
	});
}
