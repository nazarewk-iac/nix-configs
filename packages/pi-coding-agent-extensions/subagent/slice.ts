/**
 * Slice planning for oversized artifacts.
 *
 * A constrained summarizer cannot "split the file itself": the act of reading is what overflows
 * its window. So the split must happen before the model sees anything. `planSlices` turns one
 * artifact into bounded line ranges that each fit the target model's context, and the subagent
 * tool runs one child per range.
 *
 * The budget is in TOKENS, converted to lines by a conservative characters-per-token estimate.
 * That is deliberately pessimistic: a wrong guess under-fills a slice (cheap) rather than
 * overflows it (the failure we are removing).
 */

/** Characters per token. Code and prose sit near 3.5; use 3 to stay on the safe side. */
const CHARS_PER_TOKEN = 3;
/** Fraction of the model window a single slice may claim, leaving room for the reply and prompt. */
const SLICE_FILL = 0.5;

export interface Slice {
	index: number;
	/** 1-based first line, inclusive. */
	startLine: number;
	/** 1-based last line, inclusive. */
	endLine: number;
}

export interface SlicePlan {
	slices: Slice[];
	/** Lines per slice actually used. */
	linesPerSlice: number;
	/** Total lines in the artifact. */
	totalLines: number;
	/** True when the artifact needed more than one slice. */
	chunked: boolean;
}

export interface PlanSlicesOptions {
	/** The artifact's full text. */
	text: string;
	/** The target model's served context in tokens. */
	contextTokens: number;
	/** Token headroom reserved for the child's system prompt and its answer. */
	reserveTokens?: number;
}

/**
 * Choose a line count per slice from the model window.
 *
 * Uses the LONGEST line's length rather than the mean, so one very long line (a minified file, a
 * single-line JSON blob) cannot blow the budget while the average looks fine.
 */
export function linesPerSlice(text: string, contextTokens: number, reserveTokens = 2_000): number {
	const lines = text.split("\n");
	if (lines.length === 0) return 1;
	let longest = 0;
	for (const line of lines) if (line.length > longest) longest = line.length;
	const usable = Math.max(1_000, Math.floor(contextTokens * SLICE_FILL) - reserveTokens);
	const perLine = Math.max(1, Math.ceil(longest / CHARS_PER_TOKEN));
	return Math.max(50, Math.floor(usable / perLine));
}

/** Split a artifact into slices that each fit the window. */
export function planSlices(options: PlanSlicesOptions): SlicePlan {
	const { text, contextTokens, reserveTokens } = options;
	const total = text.split("\n").length;
	const size = linesPerSlice(text, contextTokens, reserveTokens);
	const count = Math.max(1, Math.ceil(total / size));
	const slices: Slice[] = [];
	for (let index = 0; index < count; index += 1) {
		const startLine = index * size + 1;
		const endLine = Math.min(total, (index + 1) * size);
		slices.push({ index, startLine, endLine });
	}
	return { slices, linesPerSlice: size, totalLines: total, chunked: count > 1 };
}

/**
 * The instruction for one slice. It names the exact range so the child reads only that window,
 * and it asks for a compact structured summary rather than prose.
 */
export function sliceTask(path: string, slice: Slice, total: number): string {
	return [
		`Read ONLY lines ${slice.startLine}-${slice.endLine} of ${path}`,
		`(slice ${slice.index + 1} of ${total}; use read with offset=${slice.startLine - 1} limit=${
			slice.endLine - slice.startLine + 1
		}).`,
		"",
		"Return a compact structured summary of exactly those lines:",
		"- concrete facts only (paths, commands, options, commit messages, errors, exit codes);",
		"- no reasoning, no preamble, no conclusion you cannot see in the text;",
		"- if the range starts or ends mid-thought, say so in one line.",
	].join("\n");
}

/** The instruction for the merge pass over the per-slice summaries. */
export function mergeTask(path: string, summaries: string): string {
	return [
		`Below are summaries of consecutive slices of ${path}, in order.`,
		"Merge them into ONE structured summary of the whole artifact. Keep every distinct concrete",
		"fact; drop repetition; keep the original order. Do not invent anything not present.",
		"",
		summaries,
	].join("\n");
}
