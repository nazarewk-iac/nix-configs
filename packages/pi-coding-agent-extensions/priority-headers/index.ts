/**
 * Stamp every model request with its engine priority class.
 *
 * The brys engine serves a bounded pool of slots (the resident profile's `parallel`). The manager
 * admits requests into that pool by priority: `primary` (the human's own turn) beats `high`, which
 * beats `normal`, which beats `low`. Nothing is preempted — a generation cannot be cancelled
 * safely — so the class decides who takes the NEXT free slot.
 *
 * Pi sends the header, the LiteLLM gateway turns it into a `/lease` (option 2, gateway-enforced),
 * and a client that never sends the header simply counts as `normal`.
 *
 * Defaults:
 *   - an explicit `KDN_PRIORITY` wins, so a person or a script can override one process;
 *   - a delegate child (`PI_ORCHESTRATOR_CHILD=1`) is `normal`, so it never outranks the turn that
 *     asked for it;
 *   - an interactive session (a TTY) is `primary`, because a human is waiting on it;
 *   - anything else — `pi -p`, a cron job, an evaluator — is `normal`. `primary` is opt-in, never a
 *     side effect of being the top-level process.
 *
 * The class is per process, not per request: a delegate child keeps its class for its whole life,
 * which is the unit the orchestrator actually creates.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CLASSES = ["primary", "high", "normal", "low"];

function priorityClass(): string {
	const explicit = (process.env.KDN_PRIORITY || "").trim().toLowerCase();
	if (CLASSES.includes(explicit)) return explicit;
	if (process.env.PI_ORCHESTRATOR_CHILD === "1") return "normal";
	if (process.stdout.isTTY) return "primary";
	return "normal";
}

/** Only the gateway pools requests; a direct llama-swap or SaaS call has no lease to take. */
function goesThroughPool(ctx: { model?: { provider?: string } }): boolean {
	return (ctx.model?.provider ?? "").startsWith("litellm");
}

export default function (pi: ExtensionAPI) {
	pi.on("before_provider_headers", (event, ctx) => {
		if (!goesThroughPool(ctx)) return;
		event.headers["x-kdn-priority"] = priorityClass();
		try {
			ctx.ui.setStatus("priority", `prio: ${priorityClass()}`);
		} catch {
			// A non-TUI run has no status line; the header is the contract.
		}
	});
}
