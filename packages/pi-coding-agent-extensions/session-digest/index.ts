/**
 * Session tools: read Pi sessions in three widening steps.
 *
 * An agent that wants to learn what a previous session did must not load the session file: it is
 * mostly JSON framing, and a 0.5 MB file is minutes of prefill. This registers three read-only
 * tools that give progressive disclosure, cheapest first:
 *
 *   session_list   { scope? }                 which sessions exist, with stable short ids
 *   session_digest { id?, scope?, from?, to? } a compact per-step digest; every step is labelled
 *                                             with its `#n` reference and entry id
 *   session_detail { id?, refs?, from?, to?, includeMetadata? } the exact, non-truncated content
 *                                             of the steps named by the digest
 *
 * A "step" is one entry of the session file (a message, a tool result, a custom/compaction
 * event), addressed by its 1-based position; the digest prints `#n` so the agent can fetch
 * exactly those and nothing more.
 *
 * Scope: default `"repo"` is the directory of THIS session, i.e. the current repository. `"all"`
 * is an explicit opt-in to every Pi session on the machine; it is never the default because a
 * session carries prompts, file bodies and command output.
 *
 * Metadata is stripped by default in `session_detail` (usage, timestamps, ids). `includeMetadata:
 * true` returns it. Tool-result bodies are included in `detail` (that is the point of asking), but
 * the digest only ever shows their first line.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import Fuse from "fuse.js";

const MAX_SESSIONS = 200;
const DIGEST_STEP_CHARS = 160;
const DIGEST_MAX_STEPS = 400;
const DETAIL_MAX_STEPS = 40;
const DETAIL_MAX_CHARS = 60_000;

type Scope = "repo" | "all";

interface Step {
	/** 1-based index over the session's entries. Stable: it is the file order. */
	ref: number;
	type: string;
	id?: string;
	role?: string;
	toolName?: string;
	/** Short single-line label for the digest. */
	label: string;
	/** The entry as parsed, for detail. */
	raw: Record<string, unknown>;
}

function sessionsBaseDir(): string {
	const fromEnv = process.env.PI_CODING_AGENT_SESSION_DIR;
	if (fromEnv) return fromEnv;
	const agentDir = process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi", "agent");
	return path.join(agentDir, "sessions");
}

function repoDirFor(ctx: { sessionManager: { getSessionFile(): string | undefined } }): string | null {
	const file = ctx.sessionManager.getSessionFile();
	if (!file) return null;
	return path.dirname(file);
}

/** Every directory that holds session files, repo-scoped or machine-wide. */
function sessionDirs(ctx: any, scope: Scope): string[] {
	if (scope === "repo") {
		const dir = repoDirFor(ctx);
		return dir && fs.existsSync(dir) ? [dir] : [];
	}
	// "all": the base may hold per-cwd subdirectories, or session files directly.
	const base = sessionsBaseDir();
	if (!fs.existsSync(base)) return [];
	const entries = fs.readdirSync(base, { withFileTypes: true });
	const dirs = entries.filter((e) => e.isDirectory()).map((e) => path.join(base, e.name));
	return dirs.length > 0 ? dirs : [base];
}

interface SessionFile {
	id: string;
	file: string;
	dir: string;
	/** Real repository path, from the session header `cwd`. */
	repo: string;
	/** Session name from the last `session_info` entry (empty when unnamed). */
	name: string;
	size: number;
	mtime: number;
}

function shortId(file: string): string {
	const base = path.basename(file, ".jsonl");
	const underscore = base.lastIndexOf("_");
	return underscore >= 0 ? base.slice(underscore + 1) : base;
}

/** Last two path segments of a repository path, for a compact list. */
function repoShort(repo: string): string {
	const parts = repo.split("/").filter(Boolean);
	return parts.slice(-2).join("/");
}

/**
 * Read just the head of a session file: the `cwd` from the header and the last `session_info`
 * name. A 64 KiB cap keeps `scope="all"` cheap even with hundreds of sessions; both fields are
 * written near the start.
 */
function readSessionMeta(file: string): { repo: string; name: string } {
	let head: string;
	try {
		const fd = fs.openSync(file, "r");
		try {
			const buf = Buffer.alloc(65_536);
			const read = fs.readSync(fd, buf, 0, buf.length, 0);
			head = buf.subarray(0, read).toString("utf8");
		} finally {
			fs.closeSync(fd);
		}
	} catch {
		return { repo: "", name: "" };
	}
	let repo = "";
	let name = "";
	for (const line of head.split("\n")) {
		if (!line.includes('"session') && !line.includes('"cwd"') && !line.includes('"name"')) continue;
		let entry: Record<string, unknown>;
		try {
			entry = JSON.parse(line) as Record<string, unknown>;
		} catch {
			continue;
		}
		if (entry.type === "session" && typeof entry.cwd === "string") repo = entry.cwd;
		if (entry.type === "session_info" && typeof entry.name === "string") name = entry.name;
	}
	return { repo, name };
}

function listSessionFiles(ctx: any, scope: Scope): SessionFile[] {
	const out: SessionFile[] = [];
	for (const dir of sessionDirs(ctx, scope)) {
		let names: string[];
		try {
			names = fs.readdirSync(dir).filter((n) => n.endsWith(".jsonl"));
		} catch {
			continue;
		}
		for (const name of names) {
			const file = path.join(dir, name);
			let stat: fs.Stats;
			try {
				stat = fs.statSync(file);
			} catch {
				continue;
			}
			const meta = readSessionMeta(file);
			out.push({
				id: shortId(file),
				file,
				dir,
				repo: meta.repo,
				name: meta.name,
				size: stat.size,
				mtime: stat.mtimeMs,
			});
		}
	}
	return out.sort((a, b) => b.mtime - a.mtime).slice(0, MAX_SESSIONS);
}

/** Resolve a session id (full, short, or filename substring) to one file. */
function resolveSession(ctx: any, scope: Scope, id?: string): SessionFile | "own" | null {
	if (!id) return "own";
	const all = listSessionFiles(ctx, scope);
	const exact = all.find((s) => s.id === id);
	if (exact) return exact;
	const matches = all.filter((s) => s.id.startsWith(id) || s.file.includes(id));
	return matches.length === 1 ? matches[0] : matches.length > 1 ? null : null;
}

function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.filter((c): c is Record<string, unknown> => typeof c === "object" && c !== null)
		.map((c) => {
			if (c.type === "text" && typeof c.text === "string") return c.text;
			if (c.type === "thinking" && typeof c.thinking === "string") return c.thinking;
			return "";
		})
		.filter(Boolean)
		.join("\n");
}

function toolArgs(args: unknown): string {
	if (typeof args !== "object" || args === null) return "";
	const keep = ["agent", "model", "slice", "path", "offset", "limit", "command", "pattern", "task"];
	const bits: string[] = [];
	for (const key of keep) {
		const value = (args as Record<string, unknown>)[key];
		if (value === undefined || value === null || value === "") continue;
		let shown = typeof value === "string" ? value : JSON.stringify(value);
		if (shown.length > 90) shown = `${shown.slice(0, 87)}...`;
		bits.push(`${key}=${shown}`);
	}
	return bits.join(" ");
}

function oneLine(text: string, max: number): string {
	const flat = text.replace(/\s+/g, " ").trim();
	return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

function parseEntries(lines: string[]): Step[] {
	const steps: Step[] = [];
	for (const line of lines) {
		if (!line.trim()) continue;
		let entry: Record<string, unknown>;
		try {
			entry = JSON.parse(line) as Record<string, unknown>;
		} catch {
			continue;
		}
		const ref = steps.length + 1;
		const type = String(entry.type ?? "?");
		if (type === "message") {
			const message = (entry.message ?? {}) as Record<string, unknown>;
			const role = String(message.role ?? "?");
			const toolName = message.toolName ? String(message.toolName) : undefined;
			let label = "";
			if (role === "assistant") {
				const calls = (message.content as unknown[] | undefined)?.filter(
					(c): c is Record<string, unknown> => typeof c === "object" && c !== null && c.type === "toolCall",
				);
				if (calls && calls.length > 0) {
					label = calls.map((c) => `CALL ${c.toolName} ${toolArgs(c.arguments)}`).join(" | ");
				} else {
					label = oneLine(textOf(message.content), DIGEST_STEP_CHARS);
				}
			} else if (role === "toolResult") {
				label = `RESULT ${toolName ?? "?"}: ${oneLine(textOf(message.content), 100)}`;
			} else {
				label = oneLine(textOf(message.content), DIGEST_STEP_CHARS);
			}
			steps.push({ ref, type, id: entry.id as string | undefined, role, toolName, label, raw: entry });
		} else if (type === "custom" || type === "custom_message") {
			const customType = String(entry.customType ?? "");
			steps.push({
				ref,
				type,
				id: entry.id as string | undefined,
				label: `[${customType || type}]`,
				raw: entry,
			});
		} else {
			steps.push({ ref, type, id: entry.id as string | undefined, label: `[${type}]`, raw: entry });
		}
	}
	return steps;
}

function readSteps(target: SessionFile | "own", ctx: any): { steps: Step[]; origin: string } {
	if (target === "own") {
		const entries = ctx.sessionManager.getEntries() as unknown[];
		const steps = parseEntries(entries.map((e) => JSON.stringify(e)));
		return { steps, origin: "this session" };
	}
	const lines = fs.readFileSync(target.file, "utf8").split("\n");
	return { steps: parseEntries(lines), origin: `${target.id} (${target.name})` };
}

function rangeOf(params: { refs?: number[]; from?: number; to?: number }): Set<number> | null {
	if (params.refs && params.refs.length > 0) return new Set(params.refs);
	if (params.from !== undefined || params.to !== undefined) {
		const from = Math.max(1, params.from ?? 1);
		const to = params.to ?? Number.MAX_SAFE_INTEGER;
		const set = new Set<number>();
		for (let ref = from; ref <= to; ref += 1) set.add(ref);
		return set;
	}
	return null;
}

function digestText(origin: string, steps: Step[], want: Set<number> | null): string {
	const selected = steps.filter((s) => (want ? want.has(s.ref) : true)).slice(0, DIGEST_MAX_STEPS);
	const counts = new Map<string, number>();
	for (const s of steps) {
		const key = s.role ? `${s.type}/${s.role}` : s.type;
		counts.set(key, (counts.get(key) ?? 0) + 1);
	}
	const summary = [...counts.entries()].map(([k, v]) => `${k}=${v}`).join(" ");
	const header = `session ${origin}: ${steps.length} steps (${summary})\n` +
		`call session_detail with refs=[...] for exact content of any step\n`;
	const body = selected
		.map((s) => `#${s.ref}${s.role ? "" : ` ${s.type}`} ${s.label}`)
		.join("\n");
	const more = selected.length < steps.filter((s) => (want ? want.has(s.ref) : true)).length
		? `\n(digest truncated at ${DIGEST_MAX_STEPS} steps; narrow with from/to or refs)`
		: "";
	return `${header}\n${body}${more}`;
}

function detailText(origin: string, steps: Step[], want: Set<number> | null, includeMetadata: boolean): string {
	const selected = steps.filter((s) => (want ? want.has(s.ref) : true)).slice(0, DETAIL_MAX_STEPS);
	const blocks: string[] = [`session ${origin}: content of ${selected.length} step(s)`];
	let budget = DETAIL_MAX_CHARS;
	for (const s of selected) {
		const message = (s.raw.message ?? {}) as Record<string, unknown>;
		const parts: string[] = [`#${s.ref} ${s.type}${s.role ? `/${s.role}` : ""}`];
		if (includeMetadata) {
			if (s.id) parts.push(`id=${s.id}`);
			const usage = message.usage as Record<string, unknown> | undefined;
			if (usage) parts.push(`usage=${JSON.stringify(usage)}`);
			if (message.timestamp) parts.push(`ts=${String(message.timestamp)}`);
			if (message.model) parts.push(`model=${String(message.model)}`);
		}
		const content = textOf(message.content);
		if (content) parts.push(content);
		for (const call of (message.content as unknown[] | undefined) ?? []) {
			if (typeof call === "object" && call !== null && (call as Record<string, unknown>).type === "toolCall") {
				const c = call as Record<string, unknown>;
				parts.push(`CALL ${c.toolName} ${JSON.stringify(c.arguments)}`);
			}
		}
		if (s.type === "custom" || s.type === "custom_message") {
			parts.push(JSON.stringify(s.raw.data ?? s.raw.details ?? s.raw));
		}
		const block = parts.join("\n");
		if (block.length > budget) {
			blocks.push(`${block.slice(0, Math.max(0, budget))}\n... [truncated; narrow refs or raise the range]`);
			break;
		}
		budget -= block.length;
		blocks.push(block);
	}
	return blocks.join("\n\n");
}

/** Rank sessions against a query with Fuse.js over id, repo and name. */
function fuzzyFilter(sessions: SessionFile[], query: string): SessionFile[] {
	const fuse = new Fuse(sessions, {
		keys: [
			{ name: "name", weight: 0.5 },
			{ name: "repo", weight: 0.3 },
			{ name: "id", weight: 0.2 },
		],
		threshold: 0.45,
		ignoreLocation: true,
		minMatchCharLength: 2,
	});
	return fuse.search(query).map((r) => r.item);
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "session_list",
		label: "List sessions",
		description:
			"List Pi sessions with a stable short id, name, size, age and step count. Default scope is " +
			"this repository; pass scope=\"all\" to list every Pi session on the machine (explicit opt-in: " +
			"sessions carry prompts and file bodies).",
		parameters: Type.Object({
			scope: Type.Optional(
				Type.Union([Type.Literal("repo"), Type.Literal("all")], {
					description: 'Default "repo" (this repository). "all" lists every Pi session.',
				}),
			),
			query: Type.Optional(
				Type.String({ description: "Fuzzy match over session id, repository and name." }),
			),
		}),
		annotations: { readOnlyHint: true },
		async execute(_id: string, params: { scope?: Scope; query?: string }, _signal: unknown, _onUpdate: unknown, ctx: any) {
			const scope: Scope = params.scope ?? "repo";
			let sessions = listSessionFiles(ctx, scope);
			if (sessions.length === 0) {
				return { content: [{ type: "text", text: `no sessions (scope=${scope})` }] };
			}
			if (params.query) sessions = fuzzyFilter(sessions, params.query);
			if (sessions.length === 0) {
				return { content: [{ type: "text", text: `no sessions match "${params.query}" (scope=${scope})` }] };
			}
			const rows = sessions.map((s) => {
				const ageH = Math.max(0, Math.round((Date.now() - s.mtime) / 3_600_000));
				const repo = s.repo ? repoShort(s.repo) : "?";
				const title = s.name || "(unnamed)";
				return `${s.id}  ${(s.size / 1024).toFixed(0).padStart(6)}KiB  ${String(ageH).padStart(4)}h  ${repo}  ${title}`;
			});
			const title = params.query ? `sessions matching "${params.query}" (scope=${scope})` : `sessions (scope=${scope}, newest first)`;
			return {
				content: [
					{
						type: "text",
						text: `${title}:\nid        size      age  repo  name\n${rows.join("\n")}`,
					},
				],
			};
		},
	});

	pi.registerTool({
		name: "session_digest",
		label: "Session digest",
		description:
			"Compact per-step digest of one Pi session, every step labelled with its `#n` reference. " +
			"Default session is the current one; pass id (from session_list) for another, and from/to or " +
			"refs to narrow. This is cheap: it never loads raw file bodies. Use session_detail to read " +
			"the exact content of the steps you pick.",
		parameters: Type.Object({
			id: Type.Optional(Type.String({ description: "Session id from session_list; omit for this session." })),
			scope: Type.Optional(
				Type.Union([Type.Literal("repo"), Type.Literal("all")], { description: 'Default "repo".' }),
			),
			from: Type.Optional(Type.Number({ description: "First step reference (1-based), inclusive." })),
			to: Type.Optional(Type.Number({ description: "Last step reference, inclusive." })),
			refs: Type.Optional(Type.Array(Type.Number(), { description: "Explicit step references." })),
		}),
		annotations: { readOnlyHint: true },
		async execute(_id: string, params: any, _signal: unknown, _onUpdate: unknown, ctx: any) {
			const scope: Scope = params.scope ?? "repo";
			const target = resolveSession(ctx, scope, params.id);
			if (target === null) {
				return { content: [{ type: "text", text: `no unique session for id=${params.id} (scope=${scope})` }] };
			}
			const { steps, origin } = readSteps(target, ctx);
			return { content: [{ type: "text", text: digestText(origin, steps, rangeOf(params)) }] };
		},
	});

	pi.registerTool({
		name: "session_detail",
		label: "Session detail",
		description:
			"Exact, non-truncated content of specific session steps (refs from session_digest), or a " +
			"from/to range. Metadata (usage, timestamps, ids) is stripped by default; pass " +
			"includeMetadata=true to keep it. Use this only for the steps you actually need.",
		parameters: Type.Object({
			id: Type.Optional(Type.String({ description: "Session id; omit for this session." })),
			scope: Type.Optional(
				Type.Union([Type.Literal("repo"), Type.Literal("all")], { description: 'Default "repo".' }),
			),
			refs: Type.Optional(Type.Array(Type.Number(), { description: "Step references to return." })),
			from: Type.Optional(Type.Number({ description: "First step reference, inclusive." })),
			to: Type.Optional(Type.Number({ description: "Last step reference, inclusive." })),
			includeMetadata: Type.Optional(
				Type.Boolean({ description: "Keep usage/timestamps/ids (default false)." }),
			),
		}),
		annotations: { readOnlyHint: true },
		async execute(_id: string, params: any, _signal: unknown, _onUpdate: unknown, ctx: any) {
			const scope: Scope = params.scope ?? "repo";
			const want = rangeOf(params);
			if (!want) {
				return {
					content: [
						{ type: "text", text: "session_detail needs refs, or from/to, to avoid dumping the session" },
					],
				};
			}
			const target = resolveSession(ctx, scope, params.id);
			if (target === null) {
				return { content: [{ type: "text", text: `no unique session for id=${params.id} (scope=${scope})` }] };
			}
			const { steps, origin } = readSteps(target, ctx);
			return {
				content: [{ type: "text", text: detailText(origin, steps, want, params.includeMetadata === true) }],
			};
		},
	});
}
