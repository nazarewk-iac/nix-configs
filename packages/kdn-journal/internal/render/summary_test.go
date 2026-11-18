package render_test

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/journal"
	"kdn-journal/internal/render"
	"kdn-journal/internal/sessionid"
)

func TestSummaryShowsAtuinLink(t *testing.T) {
	s := &journal.Session{
		Name: "opencode 20261116 ses_x",
		Sidecar: &sessionid.Sidecar{Atuin: sessionid.Atuin{
			ThreadID:     "01a1e074b8757243b1ff42e3613a72a5",
			MessageCount: 728,
			Model:        "deepseek-v4.1-flash-1017",
		}},
	}
	var buf bytes.Buffer
	if err := render.Summary(&buf, render.Options{Width: 120, ShowAtuin: true, Now: time.Now()}, s, nil); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	for _, want := range []string{"ATUIN", "01a1e074b8757243b1ff42e3613a72a5", "728 messages", "deepseek-v4.1-flash-1017"} {
		if !strings.Contains(out, want) {
			t.Errorf("summary missing %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "728 728") {
		t.Errorf("summary repeats the message count:\n%s", out)
	}
}

func TestSummaryAtuinNotLinked(t *testing.T) {
	s := &journal.Session{Name: "opencode 20261116 ses_x"}
	var buf bytes.Buffer
	if err := render.Summary(&buf, render.Options{Width: 100, ShowAtuin: true, Now: time.Now()}, s, nil); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(buf.String(), "ATUIN    not linked") {
		t.Errorf("summary missing the not-linked line:\n%s", buf.String())
	}
}

func TestSummaryHidesAtuinByDefault(t *testing.T) {
	s := &journal.Session{
		Name:    "opencode 20261116 ses_x",
		Sidecar: &sessionid.Sidecar{Atuin: sessionid.Atuin{ThreadID: "01a1e074"}},
	}
	var buf bytes.Buffer
	if err := render.Summary(&buf, render.Options{Width: 100, Now: time.Now()}, s, nil); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(buf.String(), "ATUIN") {
		t.Errorf("summary shows the Atuin line without --atuin:\n%s", buf.String())
	}
}

func TestSessionsShowsAtuinSuffix(t *testing.T) {
	s := &journal.Session{
		Date:    "2026-11-16",
		Harness: "opencode",
		Name:    "opencode 20261116 ses_x",
		ID:      "ses_x",
		Sidecar: &sessionid.Sidecar{Atuin: sessionid.Atuin{ThreadID: "01a1e074"}},
	}
	var buf bytes.Buffer
	if err := render.Sessions(&buf, render.Options{Width: 200, ShowAtuin: true, Now: time.Now()}, []*journal.Session{s}, 0); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(buf.String(), "atuin:01a1e074") {
		t.Errorf("sessions line missing the Atuin suffix:\n%s", buf.String())
	}
}
