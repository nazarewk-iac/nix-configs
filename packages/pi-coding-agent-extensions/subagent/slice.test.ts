import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { linesPerSlice, mergeTask, planSlices, sliceTask } from "./slice.ts";

const textOf = (lines: number, width = 80): string =>
	Array.from({ length: lines }, (_, i) => `line ${i + 1}`.padEnd(width, "x")).join("\n");

describe("linesPerSlice", () => {
	it("keeps a slice under half the model window", () => {
		const text = textOf(2_800);
		const size = linesPerSlice(text, 16_384);
		// Worst-case tokens for `size` lines must stay below the 50% fill budget.
		assert.ok((size * 81) / 3 < 16_384 * 0.5);
	});

	it("uses the longest line, so one long line cannot blow the budget", () => {
		const withBlob = `short\n${"z".repeat(40_000)}\nshort`;
		assert.equal(linesPerSlice(withBlob, 16_384), 50);
	});

	it("has a floor so a huge window does not become one slice of millions of lines", () => {
		assert.ok(linesPerSlice("a\nb", 1_000_000_000) >= 50);
	});
});

describe("planSlices", () => {
	it("covers every line exactly once", () => {
		const plan = planSlices({ text: textOf(1_000), contextTokens: 16_384 });
		assert.equal(plan.slices[0]?.startLine, 1);
		assert.equal(plan.slices.at(-1)?.endLine, plan.totalLines);
		for (let i = 1; i < plan.slices.length; i += 1) {
			assert.equal(plan.slices[i]?.startLine, (plan.slices[i - 1]?.endLine ?? 0) + 1);
		}
	});

	it("reports chunked only when more than one slice is needed", () => {
		assert.equal(planSlices({ text: textOf(10), contextTokens: 16_384 }).chunked, false);
		assert.equal(planSlices({ text: textOf(5_000), contextTokens: 16_384 }).chunked, true);
	});
});

describe("sliceTask", () => {
	it("precomputes the 1-indexed offset so the child does no arithmetic", () => {
		const task = sliceTask("/a/b.md", { index: 2, startLine: 201, endLine: 400 }, 5);
		assert.ok(String(task).includes("lines 201-400"));
		// read's offset is 1-indexed: the offset IS the start line, not start-1.
		assert.ok(String(task).includes("offset=201"));
		assert.ok(String(task).includes("limit=200"));
		assert.ok(String(task).includes("chunk 3 of 5"));
		assert.ok(String(task).includes("CHUNK 3"));
	});
});

describe("mergeTask", () => {
	it("embeds the slice summaries and forbids invention", () => {
		const task = mergeTask("/a/b.md", "### slice 1\nfoo\n\n### slice 2\nbar");
		assert.ok(String(task).includes("/a/b.md"));
		assert.ok(String(task).includes("### slice 1"));
		assert.match(task, /invent/);
	});
});
