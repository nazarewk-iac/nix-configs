/**
 * Context gate, as a companion extension to pi-orchestrator.
 *
 * Why a separate extension and not a patch: pi-orchestrator is vendored at a pinned commit, so
 * editing its source means re-doing the edit on every bump. This registers one small tool beside
 * `delegate` instead, and the orchestrator's prompt requires it before any large delegation.
 *
 * The tool is `measure`:
 *   { action: "check", path }        -> { bytes, lines, fits: {ok, reason, fitting} }
 *   { action: "check", inputBytes }  -> same, for a size the caller already knows
 *
 * It reads the fleet's `/v1/models` for real served context per alias (llama-swap publishes
 * `context_length`), caches it briefly, and DEGRADES TO ALLOW when the fleet is unreachable: a
 * network fault must never block work.
 */
import { checkInput, measureFile } from "./context-gate.js";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "measure",
		label: "Measure",
		description:
			"Size a file or a known byte count and check it against the served context of a model " +
			"alias. Use BEFORE delegating a large input: if the check fails, the call names the " +
			"aliases that would fit, or tells you to reduce the input. Actions: " +
			"{action:'check', path} or {action:'check', inputBytes}.",
		parameters: Type.Object({
			path: Type.Optional(Type.String({ description: "Path to a file to size" })),
			inputBytes: Type.Optional(Type.Number({ description: "A size you already know" })),
			agent: Type.Optional(
				Type.String({ description: "Agent whose model to check against; defaults to scout" }),
			),
		}),
		async execute(_id: string, params: any) {
			let bytes = params?.inputBytes;
			let lines: number | undefined;
			if (bytes === undefined && params?.path) {
				try {
					const m = measureFile(params.path);
					if (!m) {
						return {
							content: [{ type: "text", text: `not a regular file: ${params.path}` }],
							isError: true,
						};
					}
					bytes = m.bytes;
					lines = m.lines;
				} catch (e: any) {
					return {
						content: [{ type: "text", text: `cannot read ${params.path}: ${e?.message ?? e}` }],
						isError: true,
					};
				}
			}
			if (bytes === undefined) {
				return {
					content: [{ type: "text", text: "give either `path` or `inputBytes`" }],
					isError: true,
				};
			}

			// The agent's model: a fleet agent file names it; the fallback is the cheap scout tier.
			const agentModels: Record<string, string> = { scout: "brys/code-std-fast" };
			const model = agentModels[params?.agent ?? "scout"] ?? "brys/code-std-fast";
			const verdict = await checkInput(model, bytes);

			const lines_ = [
				`bytes=${bytes}${lines !== undefined ? ` lines=${lines}` : ""} model=${model}`,
				verdict.ok
					? verdict.assumed
						? "fits: UNKNOWN (fleet unreachable; allowed rather than blocking)"
						: `fits: yes (context ${verdict.context}, ~${verdict.tokens} tokens)`
					: `fits: NO. ${verdict.reason}`,
			];
			if (!verdict.ok && verdict.fitting) {
				lines_.push(`fitting aliases: ${verdict.fitting.join(", ")}`);
			}
			return { content: [{ type: "text", text: lines_.join("\n") }] };
		},
	});
}
