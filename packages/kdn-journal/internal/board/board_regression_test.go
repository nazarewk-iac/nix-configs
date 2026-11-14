package board_test

import (
	"testing"
	"time"

	"kdn-journal/internal/board"
)

func TestNestedBulletsCountOnce(t *testing.T) {
	b, err := board.Parse([]byte("## Now\n\n- parent\n  - child\n  - child2\n"), "board.md", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if got := b.Counts().Open; got != 1 {
		t.Errorf("Open = %d, want 1 (the nested bullets are part of the parent)", got)
	}
}

func TestTableAfterPipedProse(t *testing.T) {
	data := "## Now\n\nUse `a | b` here.\n| Item | State |\n| --- | --- |\n| a | open |\n"
	b, err := board.Parse([]byte(data), "board.md", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if got := b.Counts().Open; got != 1 {
		t.Errorf("Open = %d, want 1; the table after a piped prose line was lost", got)
	}
}

func TestOneDashSeparator(t *testing.T) {
	data := "## Now\n\n| Item | State |\n|-|-|\n| a | open |\n"
	b, err := board.Parse([]byte(data), "board.md", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if got := b.Counts().Open; got != 1 {
		t.Errorf("Open = %d, want 1 for a one-dash separator", got)
	}
}

func TestDroppedItemPreventsDoneStatus(t *testing.T) {
	data := "## Done\n\n- [x] finished\n\n## Notes\n\n- old idea — **dropped**\n"
	b, err := board.Parse([]byte(data), "board.md", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if b.Status == "done" {
		t.Errorf("Status = done with a dropped item; want unknown or active")
	}
}
