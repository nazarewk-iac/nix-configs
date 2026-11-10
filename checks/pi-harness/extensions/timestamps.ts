/**
 * Timestamp lines above each message.
 *
 * Pi does not expose built-in message rendering to extensions (messageRenderers /
 * entryRenderers are keyed by customType only), so this appends a durable, NON-context
 * entry (pi.appendEntry) at each message boundary and renders it as a dim [HH:MM:SS]
 * line. Custom entries are stored in the session JSONL but never sent to the model.
 *
 *  - input         -> above the user's message
 *  - message_start -> above an assistant message
 *  - tool_call     -> above a tool call/result
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

interface Stamp {
	at: number;
	role: string;
}

function hhmmss(ms: number): string {
	return new Date(ms).toLocaleTimeString(undefined, { hour12: false });
}

export default function (pi: ExtensionAPI) {
	pi.registerEntryRenderer<Stamp>("kdn-timestamp", (entry, _opts, theme) => {
		const data = entry.data ?? { at: Date.now(), role: "" };
		const label = `[${hhmmss(data.at)}]${data.role ? " " + data.role : ""}`;
		return new Text(theme.fg("dim", label), 0, 0);
	});

	const stamp = (role: string) => pi.appendEntry<Stamp>("kdn-timestamp", { at: Date.now(), role });

	pi.on("input", () => {
		stamp("user");
	});
	pi.on("message_start", (event) => {
		if (event.message?.role === "assistant") stamp("assistant");
	});
	pi.on("tool_call", () => {
		stamp("tool");
	});
}
