package frontmatter_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"kdn-journal/internal/frontmatter"
)

func TestParseSplitsFrontmatterFromBody(t *testing.T) {
	data := []byte("---\ntype: Task\ntitle: Example\n---\n# Heading\n\nBody text.\n")
	doc := frontmatter.Parse(data)

	if !doc.HasFrontmatter {
		t.Fatal("HasFrontmatter = false, want true")
	}
	if doc.FrontmatterError != "" {
		t.Errorf("FrontmatterError = %q, want empty", doc.FrontmatterError)
	}
	if got := doc.String("type"); got != "Task" {
		t.Errorf("String(type) = %q, want %q", got, "Task")
	}
	if got := doc.String("title"); got != "Example" {
		t.Errorf("String(title) = %q, want %q", got, "Example")
	}
	// The closing delimiter is not part of Body; everything after it is untouched.
	if strings.HasPrefix(string(doc.Body), "---\n") {
		t.Errorf("Body = %q, want the closing delimiter excluded", doc.Body)
	}
	if !strings.HasPrefix(string(doc.Body), "# Heading\n") {
		t.Errorf("Body = %q, want it to start with the body heading", doc.Body)
	}
	if !strings.Contains(string(doc.Body), "# Heading\n\nBody text.\n") {
		t.Errorf("Body = %q, want it to contain the body text", doc.Body)
	}
	if string(doc.Raw) != string(data) {
		t.Errorf("Raw = %q, want the input unchanged", doc.Raw)
	}
}

func TestParseDotDotDotTerminator(t *testing.T) {
	doc := frontmatter.Parse([]byte("---\ntype: Task\n...\nbody\n"))
	if !doc.HasFrontmatter {
		t.Fatal("HasFrontmatter = false, want true")
	}
	if got := doc.String("type"); got != "Task" {
		t.Errorf("String(type) = %q, want %q", got, "Task")
	}
	if !strings.Contains(string(doc.Body), "body") {
		t.Errorf("Body = %q, want it to contain the body", doc.Body)
	}
}

func TestParseMissingFrontmatter(t *testing.T) {
	for _, tc := range []struct {
		name string
		data string
	}{
		{name: "plain markdown", data: "# Just markdown\n\nNo frontmatter here.\n"},
		{name: "empty", data: ""},
		{name: "opening delimiter only", data: "---\ntype: Task\n"},
		{name: "leading blank line", data: "\n---\ntype: Task\n---\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			doc := frontmatter.Parse([]byte(tc.data))
			if doc.HasFrontmatter {
				t.Fatalf("HasFrontmatter = true, want false for %q", tc.data)
			}
			if string(doc.Body) != string(doc.Raw) {
				t.Errorf("Body = %q, want Raw = %q", doc.Body, doc.Raw)
			}
			if doc.Values == nil {
				t.Error("Values is nil, want an empty map")
			}
			if len(doc.Values) != 0 {
				t.Errorf("Values = %v, want empty", doc.Values)
			}
			if doc.FrontmatterError != "" {
				t.Errorf("FrontmatterError = %q, want empty", doc.FrontmatterError)
			}
		})
	}
}

func TestParseInvalidYAMLUsesFallback(t *testing.T) {
	// `description: Suite: a harness step` is invalid YAML because of the unquoted `: `.
	data := []byte("---\ntype: Task\ndescription: Suite: a harness step\nstatus: in-progress\ntags:\n  - parser\n  - tests\n---\nbody\n")
	doc := frontmatter.Parse(data)

	if !doc.HasFrontmatter {
		t.Fatal("HasFrontmatter = false, want true")
	}
	if doc.FrontmatterError == "" {
		t.Fatal("FrontmatterError is empty, want the YAML error")
	}
	if got := doc.String("type"); got != "Task" {
		t.Errorf("String(type) = %q, want %q", got, "Task")
	}
	if got := doc.String("description"); got != "Suite: a harness step" {
		t.Errorf("String(description) = %q, want %q", got, "Suite: a harness step")
	}
	if got := doc.String("status"); got != "in-progress" {
		t.Errorf("String(status) = %q, want %q", got, "in-progress")
	}
	if got := doc.Strings("tags"); len(got) != 2 || got[0] != "parser" || got[1] != "tests" {
		t.Errorf("Strings(tags) = %v, want [parser tests]", got)
	}
}

func TestFallbackRemovesQuotesAndInlineComment(t *testing.T) {
	data := []byte("---\ndescription: Suite: a step\ntitle: \"Quoted title\"\nstatus: open # trailing note\nowner:\n  - alice\n---\nbody\n")
	doc := frontmatter.Parse(data)

	if doc.FrontmatterError == "" {
		t.Fatal("FrontmatterError is empty, want the YAML error")
	}
	if got := doc.String("title"); got != "Quoted title" {
		t.Errorf("String(title) = %q, want %q", got, "Quoted title")
	}
	if got := doc.String("status"); got != "open" {
		t.Errorf("String(status) = %q, want %q", got, "open")
	}
	if got := doc.Strings("owner"); len(got) != 1 || got[0] != "alice" {
		t.Errorf("Strings(owner) = %v, want [alice]", got)
	}
}

func TestParseKeepsUnknownKeys(t *testing.T) {
	doc := frontmatter.Parse([]byte("---\ntype: Task\ncustom_key: hello\nempty:\n---\n"))
	if doc.FrontmatterError != "" {
		t.Fatalf("FrontmatterError = %q, want empty", doc.FrontmatterError)
	}
	if got := doc.String("custom_key"); got != "hello" {
		t.Errorf("String(custom_key) = %q, want %q", got, "hello")
	}
	if got := doc.String("empty"); got != "" {
		t.Errorf("String(empty) = %q, want empty", got)
	}
	if got := doc.String("missing"); got != "" {
		t.Errorf("String(missing) = %q, want empty", got)
	}
	if got := doc.Strings("missing"); got != nil {
		t.Errorf("Strings(missing) = %v, want nil", got)
	}
}

func TestStringsListVersusCommaScalar(t *testing.T) {
	for _, tc := range []struct {
		name string
		data string
		want []string
	}{
		{
			name: "yaml list",
			data: "---\ntags:\n  - alpha\n  - beta\n---\n",
			want: []string{"alpha", "beta"},
		},
		{
			name: "flow list",
			data: "---\ntags: [alpha, beta]\n---\n",
			want: []string{"alpha", "beta"},
		},
		{
			name: "comma scalar",
			data: "---\ntags: alpha, beta\n---\n",
			want: []string{"alpha", "beta"},
		},
		{
			name: "single scalar",
			data: "---\ntags: alpha\n---\n",
			want: []string{"alpha"},
		},
		{
			name: "comma scalar with blanks",
			data: "---\ntags: alpha, , beta,\n---\n",
			want: []string{"alpha", "beta"},
		},
		{
			name: "empty scalar",
			data: "---\ntags: \"  \"\n---\n",
			want: nil,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			doc := frontmatter.Parse([]byte(tc.data))
			got := doc.Strings("tags")
			if len(got) != len(tc.want) {
				t.Fatalf("Strings(tags) = %v, want %v", got, tc.want)
			}
			for i := range tc.want {
				if got[i] != tc.want[i] {
					t.Fatalf("Strings(tags) = %v, want %v", got, tc.want)
				}
			}
		})
	}
}

func TestTimeTimestamps(t *testing.T) {
	data := []byte("---" +
		"\nrfc3339: 2026-11-15T20:10:00+01:00" +
		"\ndate: 2026-11-15" +
		"\nspace: \"2026-11-15 20:10:00 +0100\"" +
		"\nbad: not a timestamp" +
		"\n---\n")
	doc := frontmatter.Parse(data)
	if doc.FrontmatterError != "" {
		t.Fatalf("FrontmatterError = %q, want empty", doc.FrontmatterError)
	}

	cases := []struct {
		key  string
		want time.Time
	}{
		{
			key:  "rfc3339",
			want: time.Date(2026, 11, 15, 20, 10, 0, 0, time.FixedZone("", 3600)),
		},
		{
			key:  "date",
			want: time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC),
		},
		{
			key:  "space",
			want: time.Date(2026, 11, 15, 20, 10, 0, 0, time.FixedZone("", 3600)),
		},
	}
	for _, tc := range cases {
		t.Run(tc.key, func(t *testing.T) {
			got, ok := doc.Time(tc.key)
			if !ok {
				t.Fatalf("Time(%s) ok = false, want true", tc.key)
			}
			if !got.Equal(tc.want) {
				t.Errorf("Time(%s) = %s, want %s", tc.key, got, tc.want)
			}
		})
	}

	if _, ok := doc.Time("bad"); ok {
		t.Error("Time(bad) ok = true, want false")
	}
	if _, ok := doc.Time("missing"); ok {
		t.Error("Time(missing) ok = true, want false")
	}
}

func TestParseTimeLayouts(t *testing.T) {
	cases := []struct {
		value string
		want  time.Time
	}{
		{value: "2026-11-15T20:10:00+01:00", want: time.Date(2026, 11, 15, 20, 10, 0, 0, time.FixedZone("", 3600))},
		{value: "2026-11-15T19:10:00Z", want: time.Date(2026, 11, 15, 19, 10, 0, 0, time.UTC)},
		{value: "2026-11-15 20:10:00 +0100", want: time.Date(2026, 11, 15, 20, 10, 0, 0, time.FixedZone("", 3600))},
		{value: "2026-11-15 20:10:00", want: time.Date(2026, 11, 15, 20, 10, 0, 0, time.UTC)},
		{value: "2026-11-15", want: time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC)},
		{value: "  2026-11-15  ", want: time.Date(2026, 11, 15, 0, 0, 0, 0, time.UTC)},
	}
	for _, tc := range cases {
		got, ok := frontmatter.ParseTime(tc.value)
		if !ok {
			t.Errorf("ParseTime(%q) ok = false, want true", tc.value)
			continue
		}
		if !got.Equal(tc.want) {
			t.Errorf("ParseTime(%q) = %s, want %s", tc.value, got, tc.want)
		}
	}
	for _, value := range []string{"", "   ", "yesterday", "2026-13-45"} {
		if _, ok := frontmatter.ParseTime(value); ok {
			t.Errorf("ParseTime(%q) ok = true, want false", value)
		}
	}
}

func TestSetScalarPreservesBodyCommentsAndFence(t *testing.T) {
	original := "---\ntype: Task\nstatus: open\n# keep this comment\ntags:\n  - alpha\n---\n\nStatus: open\n\n~~~yaml\nstatus: active\n~~~\n"
	want := strings.Replace(original, "status: open\n", "status: in-progress\n", 1)

	got, err := frontmatter.SetScalar([]byte(original), "status", "in-progress")
	if err != nil {
		t.Fatalf("SetScalar: %v", err)
	}
	if string(got) != want {
		t.Fatalf("SetScalar result = %q, want %q", got, want)
	}
	if !strings.Contains(string(got), "status: active") {
		t.Error("the fenced `status: active` line in the body was changed")
	}
	if !strings.Contains(string(got), "# keep this comment") {
		t.Error("the frontmatter comment was dropped")
	}
	if doc := frontmatter.Parse(got); doc.String("status") != "in-progress" {
		t.Errorf("re-parsed status = %q, want %q", doc.String("status"), "in-progress")
	}
}

func TestSetScalarPreservesCRLF(t *testing.T) {
	original := "---\r\ntype: Task\r\nstatus: open\r\n---\r\nbody line\r\n"
	want := "---\r\ntype: Task\r\nstatus: done\r\n---\r\nbody line\r\n"

	got, err := frontmatter.SetScalar([]byte(original), "status", "done")
	if err != nil {
		t.Fatalf("SetScalar: %v", err)
	}
	if string(got) != want {
		t.Fatalf("SetScalar result = %q, want %q", got, want)
	}
}

func TestSetScalarInsertsMissingKey(t *testing.T) {
	original := "---\ntype: Task\n---\nbody\n"
	want := "---\ntype: Task\nstatus: open\n---\nbody\n"

	got, err := frontmatter.SetScalar([]byte(original), "status", "open")
	if err != nil {
		t.Fatalf("SetScalar: %v", err)
	}
	if string(got) != want {
		t.Fatalf("SetScalar result = %q, want %q", got, want)
	}
}

func TestSetScalarInsertsIntoEmptyFrontmatter(t *testing.T) {
	original := "---\n---\nbody\n"
	got, err := frontmatter.SetScalar([]byte(original), "status", "open")
	if err != nil {
		t.Fatalf("SetScalar: %v", err)
	}
	if doc := frontmatter.Parse(got); !doc.HasFrontmatter || doc.String("status") != "open" {
		t.Fatalf("re-parsed document = %+v, want status open with frontmatter", doc)
	}
	if !strings.HasSuffix(string(got), "---\nbody\n") {
		t.Errorf("body was not preserved: %q", got)
	}
}

func TestSetScalarIgnoresNestedKey(t *testing.T) {
	original := "---\nmeta:\n  status: deep\nstatus: open\n---\n"
	want := "---\nmeta:\n  status: deep\nstatus: in-progress\n---\n"

	got, err := frontmatter.SetScalar([]byte(original), "status", "in-progress")
	if err != nil {
		t.Fatalf("SetScalar: %v", err)
	}
	if string(got) != want {
		t.Fatalf("SetScalar result = %q, want %q", got, want)
	}
}

func TestSetScalarQuoting(t *testing.T) {
	cases := []struct {
		name  string
		value string
		want  string
	}{
		{name: "safe path", value: "/a/b.md", want: "path: /a/b.md"},
		{name: "empty", value: "", want: `path: ""`},
		{name: "spaces", value: "in progress", want: "path: 'in progress'"},
		{name: "apostrophe", value: "it's done", want: "path: 'it''s done'"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := frontmatter.SetScalar([]byte("---\ntype: Task\n---\n"), "path", tc.value)
			if err != nil {
				t.Fatalf("SetScalar: %v", err)
			}
			if !strings.Contains(string(got), tc.want) {
				t.Errorf("SetScalar result = %q, want it to contain %q", got, tc.want)
			}
		})
	}
}

func TestSetScalarWithoutFrontmatter(t *testing.T) {
	if _, err := frontmatter.SetScalar([]byte("body only\n"), "status", "open"); err == nil {
		t.Fatal("SetScalar error = nil, want an error")
	}
}

func TestParseFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "definition.md")
	const content = "---\ntype: Task\nstatus: open\n---\nbody\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	doc, err := frontmatter.ParseFile(path)
	if err != nil {
		t.Fatalf("ParseFile: %v", err)
	}
	if !doc.HasFrontmatter || doc.String("status") != "open" {
		t.Errorf("ParseFile = %+v, want frontmatter with status open", doc)
	}

	if _, err := frontmatter.ParseFile(filepath.Join(dir, "absent.md")); err == nil {
		t.Fatal("ParseFile error = nil for a missing file, want an error")
	}
}
