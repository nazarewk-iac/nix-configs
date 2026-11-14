package render

import (
	"strings"
	"testing"
)

func TestTruncateANSI(t *testing.T) {
	line := statusPaint("active", true) + " " + strings.Repeat("x", 40)
	got := truncate(line, 20)
	if visibleLen(got) > 20 {
		t.Errorf("visible length = %d, want at most 20: %q", visibleLen(got), got)
	}
	if !strings.Contains(got, "…") {
		t.Errorf("truncated line has no ellipsis: %q", got)
	}
	if !strings.HasSuffix(got, ansiReset) {
		t.Errorf("colored truncated line does not reset: %q", got)
	}
}

func TestStatusPaintDisabled(t *testing.T) {
	if got := statusPaint("done", false); got != "[done]" {
		t.Errorf("statusPaint(done, false) = %q", got)
	}
	if got := statusPaint("done", true); !strings.Contains(got, "[done]") {
		t.Errorf("statusPaint(done, true) = %q", got)
	}
}
