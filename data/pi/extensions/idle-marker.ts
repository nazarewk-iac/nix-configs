/**
 * Idle-marker extension.
 *
 * Pi emits `agent_settled` when it will not continue automatically — the true
 * "done, waiting for input" signal (see docs/extensions.md and notify.ts). This
 * extension mirrors that signal into a file at $PI_IDLE_MARKER so a supervisor can
 * poll a file instead of scraping the pane.
 *
 * States: "running" while a run is in flight, "idle" once it settles, "aborted"
 * if the run was aborted. The file is created at startup as "idle".
 *
 * Subagents (spawned with `--no-session` by the subagent extension) inherit this
 * env var; they are skipped so only the top-level Pi writes the marker.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";

export default function (pi: ExtensionAPI) {
	const file = process.env.PI_IDLE_MARKER;
	if (!file) return; // opt-in only
	if (process.argv.includes("--no-session")) return; // skip subagents

	const put = (state: string) => {
		try {
			fs.writeFileSync(file, `${state}\n`);
		} catch {
			/* best effort */
		}
	};

	pi.on("session_start", async () => put("idle"));
	pi.on("before_agent_start", async () => put("running"));
	pi.on("agent_settled", async (event: { aborted?: boolean }) =>
		put(event?.aborted ? "aborted" : "idle"),
	);
}
