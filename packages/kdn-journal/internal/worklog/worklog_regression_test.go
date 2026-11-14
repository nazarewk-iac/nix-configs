package worklog_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/worklog"
)

func TestBodyKeepsBulletLines(t *testing.T) {
	data := []byte("# W\n\n## 2026-11-15T10:00:00Z — run\n\n- bullet one\n- bullet two\nplain prose\n")
	w := worklog.Parse(data, "x.md", time.Now())
	if len(w.Entries) != 1 {
		t.Fatalf("entries = %d, want 1", len(w.Entries))
	}
	body := w.Entries[0].Body
	for _, want := range []string{"- bullet one", "- bullet two", "plain prose"} {
		if !strings.Contains(body, want) {
			t.Errorf("body %q does not contain %q", body, want)
		}
	}
}

func TestEntryJSONOmitsZeroTimestamp(t *testing.T) {
	data, err := json.Marshal(worklog.Entry{Heading: "undated"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "0001-01-01") {
		t.Errorf("JSON contains a zero timestamp: %s", data)
	}
	if strings.Contains(string(data), `"timestamp"`) {
		t.Errorf("JSON contains a timestamp field for an undated entry: %s", data)
	}
}
