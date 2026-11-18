package board_test

import (
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/board"
)

var boardModTime = time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)

func parseBoard(t *testing.T, data, path string) *board.Board {
	t.Helper()
	b, err := board.Parse([]byte(data), path, boardModTime)
	if err != nil {
		t.Fatalf("Parse(%q): %v", path, err)
	}
	return b
}

func boardTexts(items []board.Item) []string {
	out := make([]string, len(items))
	for i, item := range items {
		out[i] = item.Text
	}
	return out
}

func boardItem(t *testing.T, items []board.Item, text string) board.Item {
	t.Helper()
	for _, item := range items {
		if item.Text == text {
			return item
		}
	}
	t.Fatalf("item %q not found in %v", text, boardTexts(items))
	return board.Item{}
}

func boardSection(t *testing.T, b *board.Board, title string) board.Section {
	t.Helper()
	for _, sec := range b.Sections {
		if sec.Title == title {
			return sec
		}
	}
	t.Fatalf("section %q not found", title)
	return board.Section{}
}

func TestStructuredBoard(t *testing.T) {
	data := `---
title: Test board
status: active
description: A board
tags: [alpha, beta]
updated: 2026-11-15T10:00:00Z
---

# Board — Test board

## Status

- [x] finished thing
- [ ] open thing

## Next

- do the next thing

## Blocked

- waits on review
`
	b := parseBoard(t, data, "session/board.md")

	if !b.HasFrontmatter {
		t.Error("HasFrontmatter = false, want true")
	}
	if b.Title != "Test board" {
		t.Errorf("Title = %q, want %q", b.Title, "Test board")
	}
	if b.Description != "A board" {
		t.Errorf("Description = %q, want %q", b.Description, "A board")
	}
	if b.Status != "active" {
		t.Errorf("Status = %q, want %q", b.Status, "active")
	}
	if want := []string{"alpha", "beta"}; !reflect.DeepEqual(b.Tags, want) {
		t.Errorf("Tags = %v, want %v", b.Tags, want)
	}
	if want := time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC); !b.Updated.Equal(want) {
		t.Errorf("Updated = %s, want %s", b.Updated, want)
	}

	now := b.Items(board.KindNow)
	if len(now) != 2 {
		t.Fatalf("now items = %v, want 2", boardTexts(now))
	}
	done := boardItem(t, now, "finished thing")
	if !done.Done || !done.Checkbox {
		t.Errorf("finished thing = %+v, want done checkbox item", done)
	}
	open := boardItem(t, now, "open thing")
	if open.Done || !open.Checkbox {
		t.Errorf("open thing = %+v, want open checkbox item", open)
	}

	next := b.Items(board.KindNext)
	if want := []string{"do the next thing"}; !reflect.DeepEqual(boardTexts(next), want) {
		t.Errorf("next items = %v, want %v", boardTexts(next), want)
	}

	blocked := b.Items(board.KindBlocked)
	if len(blocked) != 1 || !blocked[0].Blocked {
		t.Errorf("blocked items = %+v, want one blocked item", blocked)
	}

	counts := b.Counts()
	wantCounts := board.Counts{Open: 2, Done: 1, Blocked: 1}
	if counts != wantCounts {
		t.Errorf("Counts = %+v, want %+v", counts, wantCounts)
	}
}

func TestBoardWithoutFrontmatter(t *testing.T) {
	data := `# Board — Real title

## Status

- [ ] one item
`
	b := parseBoard(t, data, "session/board.md")

	if b.HasFrontmatter {
		t.Error("HasFrontmatter = true, want false")
	}
	if b.Title != "Real title" {
		t.Errorf("Title = %q, want %q", b.Title, "Real title")
	}
	if !b.Updated.Equal(boardModTime) {
		t.Errorf("Updated = %s, want the mod time %s", b.Updated, boardModTime)
	}
	if got := len(b.Items(board.KindNow)); got != 1 {
		t.Errorf("now items = %d, want 1", got)
	}
}

func TestBoardTitleFallsBackToDirectory(t *testing.T) {
	data := `# Board

## Status

- [ ] one item
`
	b := parseBoard(t, data, "/tmp/sessions/abc123/board.md")
	if b.Title != "abc123" {
		t.Errorf("Title = %q, want %q", b.Title, "abc123")
	}
}

func TestBoardTitleFallsBackToBaseName(t *testing.T) {
	b := parseBoard(t, "prose only\n", "/tmp/sessions/abc123/board-track.md")
	if b.Title != "board-track" {
		t.Errorf("Title = %q, want %q", b.Title, "board-track")
	}
}

func TestFrontmatterTitleWinsOverH1(t *testing.T) {
	data := `---
title: Frontmatter title
---

# Board — Heading title

## Status

- [ ] one
`
	b := parseBoard(t, data, "session/board.md")
	if b.Title != "Frontmatter title" {
		t.Errorf("Title = %q, want %q", b.Title, "Frontmatter title")
	}
}

func TestUnstructuredBoardNoHeadings(t *testing.T) {
	data := `Loose prose with no heading.

| item | state |
| --- | --- |
| one | done |
| two | open |
`
	b := parseBoard(t, data, "/tmp/x/abc/board.md")

	if len(b.Sections) != 1 {
		t.Fatalf("Sections = %d, want 1 root section", len(b.Sections))
	}
	// A state-bearing table in an unclassified section is treated as current state.
	if b.Sections[0].Kind != board.KindNow {
		t.Errorf("root section Kind = %q, want %q", b.Sections[0].Kind, board.KindNow)
	}
	if len(b.Sections[0].Items) != 2 {
		t.Fatalf("items = %v, want 2", boardTexts(b.Sections[0].Items))
	}
	counts := b.Counts()
	if counts.Done != 1 || counts.Open != 1 {
		t.Errorf("Counts = %+v, want one done and one open", counts)
	}
	if b.Status != "active" {
		t.Errorf("Status = %q, want %q", b.Status, "active")
	}
	if b.Title != "board" {
		t.Errorf("Title = %q, want %q", b.Title, "board")
	}
}

func TestBoardWithoutStateIsUnknown(t *testing.T) {
	data := `Just a sentence.

- a lone bullet
`
	b := parseBoard(t, data, "session/board.md")

	if len(b.Sections) != 1 || len(b.Sections[0].Items) != 1 {
		t.Fatalf("Sections = %+v, want one root section with one item", b.Sections)
	}
	// A plain bullet in an unclassified section is prose, not a task item.
	if counts := b.Counts(); counts != (board.Counts{}) {
		t.Errorf("Counts = %+v, want zero", counts)
	}
	if b.Status != "unknown" {
		t.Errorf("Status = %q, want %q", b.Status, "unknown")
	}
}

func TestDateHeadedStateTable(t *testing.T) {
	data := `## 2026-11-13

| item | state |
| --- | --- |
| wire the parser | done |
| write tests | in progress |
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if want := []string{"wire the parser", "write tests"}; !reflect.DeepEqual(boardTexts(now), want) {
		t.Fatalf("now items = %v, want %v", boardTexts(now), want)
	}
	if !boardItem(t, now, "wire the parser").Done {
		t.Error("wire the parser is not done")
	}
	if boardItem(t, now, "write tests").Done {
		t.Error("write tests is done, want open")
	}
	if counts := b.Counts(); counts.Done != 1 || counts.Open != 1 {
		t.Errorf("Counts = %+v, want one done and one open", counts)
	}
	if b.Status != "active" {
		t.Errorf("Status = %q, want %q", b.Status, "active")
	}
}

func TestThreeColumnItemStateWhere(t *testing.T) {
	data := `## Status

| Item | State | Where |
| --- | --- | --- |
| parser | done | internal/markdown |
| tests | blocked | ci |
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if len(now) != 2 {
		t.Fatalf("now items = %v, want 2", boardTexts(now))
	}
	parser := boardItem(t, now, "parser")
	if !parser.Done || !reflect.DeepEqual(parser.Extra, []string{"internal/markdown"}) {
		t.Errorf("parser = %+v, want done with the where column as Extra", parser)
	}
	tests := boardItem(t, now, "tests")
	if !tests.Blocked || !reflect.DeepEqual(tests.Extra, []string{"ci"}) {
		t.Errorf("tests = %+v, want blocked with the where column as Extra", tests)
	}
	if counts := b.Counts(); counts.Done != 1 || counts.Blocked != 1 {
		t.Errorf("Counts = %+v, want one done and one blocked", counts)
	}
}

func TestDoneWithOpenQualifierStaysOpen(t *testing.T) {
	data := `## State

| task | action | state |
| --- | --- | --- |
| closed | close | DONE |
| parked | close | DONE (parked, in-progress) |
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if len(now) != 2 {
		t.Fatalf("now items = %v, want 2", boardTexts(now))
	}
	if closed := boardItem(t, now, "closed"); !closed.Done {
		t.Errorf("closed = %+v, want done", closed)
	}
	if parked := boardItem(t, now, "parked"); parked.Done {
		t.Errorf("parked = %+v, want open despite the leading DONE", parked)
	}
	if counts := b.Counts(); counts.Done != 1 || counts.Open != 1 {
		t.Errorf("Counts = %+v, want one done and one open", counts)
	}
}

func TestTrackScopeStateTable(t *testing.T) {
	data := `## Tracks

| Track | Scope | State |
| --- | --- | --- |
| ssh-ca | certificates | done |
| pi | harness | open |
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if len(now) != 2 {
		t.Fatalf("now items = %v, want 2", boardTexts(now))
	}
	if got := boardItem(t, now, "ssh-ca").Extra; !reflect.DeepEqual(got, []string{"certificates"}) {
		t.Errorf("ssh-ca Extra = %v, want [certificates]", got)
	}
	if counts := b.Counts(); counts.Done != 1 || counts.Open != 1 {
		t.Errorf("Counts = %+v, want one done and one open", counts)
	}
}

func TestCheckResultTableStaysProse(t *testing.T) {
	data := `## Status

| Check | Result |
| --- | --- |
| go test | ok |
`
	b := parseBoard(t, data, "session/board.md")

	if items := b.Items(board.KindNow); len(items) != 0 {
		t.Errorf("items = %v, want none for a table without a state column", boardTexts(items))
	}
	sec := boardSection(t, b, "Status")
	if len(sec.Prose) == 0 {
		t.Fatal("Prose is empty, want the table rows as prose")
	}
	if !strings.Contains(strings.Join(sec.Prose, "\n"), "go test") {
		t.Errorf("Prose = %v, want it to contain the table rows", sec.Prose)
	}
}

func TestNotBlockersHeadingIsNext(t *testing.T) {
	data := `## Open follow-ups (not blockers)

- owner reboot
- check the logs
`
	b := parseBoard(t, data, "session/board.md")

	next := b.Items(board.KindNext)
	if want := []string{"owner reboot", "check the logs"}; !reflect.DeepEqual(boardTexts(next), want) {
		t.Errorf("next items = %v, want %v", boardTexts(next), want)
	}
	if blocked := b.Items(board.KindBlocked); len(blocked) != 0 {
		t.Errorf("blocked items = %v, want none", boardTexts(blocked))
	}
	if counts := b.Counts(); counts.Open != 2 {
		t.Errorf("Counts = %+v, want two open items", counts)
	}
}

func TestDoneSectionMarksBulletsDone(t *testing.T) {
	data := `## Done

- shipped the parser
- shipped the renderer
`
	b := parseBoard(t, data, "session/board.md")

	done := b.Items(board.KindDone)
	if len(done) != 2 {
		t.Fatalf("done items = %v, want 2", boardTexts(done))
	}
	for _, item := range done {
		if !item.Done {
			t.Errorf("item %q = %+v, want Done", item.Text, item)
		}
	}
	if counts := b.Counts(); counts.Done != 2 || counts.Open != 0 {
		t.Errorf("Counts = %+v, want two done", counts)
	}
	if b.Status != "done" {
		t.Errorf("Status = %q, want %q", b.Status, "done")
	}
}

func TestLeftoverNotesHeadingIsNotes(t *testing.T) {
	data := `## Leftover notes for the next pass

- remember to update the docs

## Done

- something shipped
`
	b := parseBoard(t, data, "session/board.md")

	sec := boardSection(t, b, "Leftover notes for the next pass")
	if sec.Kind != board.KindNotes {
		t.Errorf("section Kind = %q, want %q", sec.Kind, board.KindNotes)
	}
	if len(sec.Items) != 1 {
		t.Fatalf("notes items = %v, want 1", boardTexts(sec.Items))
	}
	// A plain bullet in a notes section is prose, not a task item.
	if counts := b.Counts(); counts.Open != 0 || counts.Done != 1 {
		t.Errorf("Counts = %+v, want zero open and one done", counts)
	}
	if b.Status != "done" {
		t.Errorf("Status = %q, want %q", b.Status, "done")
	}
}

func TestStateVocabulary(t *testing.T) {
	data := `## State

| item | state |
| --- | --- |
| a | DONE — 5 reports |
| b | COMMITTED abc123 |
| c | DROPPED by user |
| d | documented, not gated |
| e | x |
| f | fix |
| g | ✓ |
| h | blocked (waiting on review) |
| i | done: |
`
	b := parseBoard(t, data, "session/board.md")
	now := b.Items(board.KindNow)
	if len(now) != 9 {
		t.Fatalf("now items = %v, want 9", boardTexts(now))
	}

	wantDone := []string{"a", "b", "e", "g", "i"}
	for _, text := range wantDone {
		item := boardItem(t, now, text)
		if !item.Done {
			t.Errorf("item %q (state %q) = %+v, want Done", text, item.State, item)
		}
	}
	if item := boardItem(t, now, "c"); !item.Dropped {
		t.Errorf("item c = %+v, want Dropped", item)
	}
	if item := boardItem(t, now, "h"); !item.Blocked {
		t.Errorf("item h = %+v, want Blocked", item)
	}
	for _, text := range []string{"d", "f"} {
		item := boardItem(t, now, text)
		if item.Done || item.Blocked || item.Dropped {
			t.Errorf("item %q = %+v, want open", text, item)
		}
	}

	counts := b.Counts()
	want := board.Counts{Open: 2, Done: 5, Blocked: 1, Dropped: 1}
	if counts != want {
		t.Errorf("Counts = %+v, want %+v", counts, want)
	}
	if b.Status != "blocked" {
		t.Errorf("Status = %q, want %q", b.Status, "blocked")
	}
}

func TestStatePhraseOnBullet(t *testing.T) {
	data := `## Items

- 005 ssh-ca — **blocked**: waits for the owner
- 006 renderer — **done** — merged
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	blocked := boardItem(t, now, "005 ssh-ca — **blocked**: waits for the owner")
	if !blocked.Blocked || blocked.State != "blocked" {
		t.Errorf("blocked bullet = %+v, want Blocked with state %q", blocked, "blocked")
	}
	done := boardItem(t, now, "006 renderer — **done** — merged")
	if !done.Done || done.State != "done" {
		t.Errorf("done bullet = %+v, want Done with state %q", done, "done")
	}
}

func TestNestedBulletsAndContinuation(t *testing.T) {
	data := `## Items

- parent item
  - child item
    continuation of child
- second parent
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if len(now) != 3 {
		t.Fatalf("now items = %v, want 3", boardTexts(now))
	}
	if now[0].Text != "parent item" || now[0].Depth != 0 {
		t.Errorf("item 0 = %+v, want %q at depth 0", now[0], "parent item")
	}
	if now[1].Depth != 1 {
		t.Errorf("item 1 Depth = %d, want 1", now[1].Depth)
	}
	if now[1].Text != "child item continuation of child" {
		t.Errorf("item 1 Text = %q, want the continuation joined", now[1].Text)
	}
	if now[2].Text != "second parent" || now[2].Depth != 0 {
		t.Errorf("item 2 = %+v, want %q at depth 0", now[2], "second parent")
	}
}

func TestNonIndentedProseClosesBullet(t *testing.T) {
	data := `## Items

- parent item

a separate paragraph
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if len(now) != 1 {
		t.Fatalf("now items = %v, want 1", boardTexts(now))
	}
	if now[0].Text != "parent item" {
		t.Errorf("item text = %q, want %q", now[0].Text, "parent item")
	}
	sec := boardSection(t, b, "Items")
	if len(sec.Prose) == 0 {
		t.Error("Prose is empty, want the separate paragraph")
	}
}

func TestInheritedSubsectionKind(t *testing.T) {
	data := `## Items

### f. Cleanups

- clean up temp files
`
	b := parseBoard(t, data, "session/board.md")

	now := b.Items(board.KindNow)
	if want := []string{"clean up temp files"}; !reflect.DeepEqual(boardTexts(now), want) {
		t.Errorf("now items = %v, want %v", boardTexts(now), want)
	}
}

func TestFrontmatterStatusNormalization(t *testing.T) {
	cases := []struct {
		status string
		want   string
	}{
		{status: "in-progress", want: "active"},
		{status: "in progress", want: "active"},
		{status: "open", want: "active"},
		{status: "blocked", want: "blocked"},
		{status: "done", want: "done"},
		{status: "Active", want: "active"},
	}
	for _, tc := range cases {
		t.Run(tc.status, func(t *testing.T) {
			data := "---\nstatus: " + tc.status + "\n---\n\nprose only\n"
			b := parseBoard(t, data, "session/board.md")
			if b.Status != tc.want {
				t.Errorf("Status = %q, want %q", b.Status, tc.want)
			}
		})
	}
}

func TestUpdatedFallsBackToTimestamp(t *testing.T) {
	data := `---
timestamp: 2026-11-10
---

prose only
`
	b := parseBoard(t, data, "session/board.md")
	want := time.Date(2026, 11, 10, 0, 0, 0, 0, time.UTC)
	if !b.Updated.Equal(want) {
		t.Errorf("Updated = %s, want %s", b.Updated, want)
	}
}

func TestItemsReturnsFileOrder(t *testing.T) {
	data := `## Next

- first next

## Done

- first done

## Next

- second next
`
	b := parseBoard(t, data, "session/board.md")

	next := b.Items(board.KindNext)
	want := []string{"first next", "second next"}
	if !reflect.DeepEqual(boardTexts(next), want) {
		t.Errorf("next items = %v, want %v", boardTexts(next), want)
	}
	if done := b.Items(board.KindDone); len(done) != 1 {
		t.Errorf("done items = %v, want 1", boardTexts(done))
	}
}

func TestParseFile(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/board.md"
	data := `---
title: Fixture board
---

## Status

- [ ] one item
`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}

	b, err := board.ParseFile(path)
	if err != nil {
		t.Fatalf("ParseFile: %v", err)
	}
	if b.Path != path {
		t.Errorf("Path = %q, want %q", b.Path, path)
	}
	if b.Title != "Fixture board" {
		t.Errorf("Title = %q, want %q", b.Title, "Fixture board")
	}
	if b.Updated.IsZero() || !b.Updated.Equal(b.ModTime) {
		t.Errorf("Updated = %s ModTime = %s, want the mod time", b.Updated, b.ModTime)
	}
}
