package trailer

import (
	"reflect"
	"testing"
)

func TestParse(t *testing.T) {
	cases := []struct {
		name     string
		input    string
		body     string
		trailers []Trailer
	}{
		{name: "empty", input: ""},
		{name: "body only", input: "subject\n\nbody text\n", body: "subject\n\nbody text"},
		{name: "body and trailers", input: "subject\n\nbody\n\nAssisted-by: opencode:m\n", body: "subject\n\nbody",
			trailers: []Trailer{{"Assisted-by", "opencode:m"}}},
		{name: "trailers only", input: "Assisted-by: opencode:m\nSession-Id: ses_1\n",
			trailers: []Trailer{{"Assisted-by", "opencode:m"}, {"Session-Id", "ses_1"}}},
		{name: "subject directly above a trailer is not a block", input: "subject\nAssisted-by: a:b",
			body: "subject\nAssisted-by: a:b"},
		{name: "prose paragraph is not a trailer", input: "subject\n\nThis is: prose.\n", body: "subject\n\nThis is: prose."},
		{name: "fenced code is not a trailer", input: "subject\n\n```\nAssisted-by: a:b\n```\n", body: "subject\n\n```\nAssisted-by: a:b\n```"},
		{name: "list is not a trailer", input: "subject\n\n- Assisted-by: a:b\n", body: "subject\n\n- Assisted-by: a:b"},
		{name: "folded value", input: "Assisted-by: opencode:\n  deepseek\n",
			trailers: []Trailer{{"Assisted-by", "opencode: deepseek"}}},
		{name: "duplicate keys", input: "Assisted-by: a:b\nAssisted-by: c:d\n",
			trailers: []Trailer{{"Assisted-by", "a:b"}, {"Assisted-by", "c:d"}}},
		{name: "trailing blank line", input: "subject\n\nAssisted-by: a:b\n\n", body: "subject",
			trailers: []Trailer{{"Assisted-by", "a:b"}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			doc := Parse(tc.input)
			if got := doc.Body(); got != tc.body {
				t.Fatalf("Body() = %q, want %q", got, tc.body)
			}
			if !reflect.DeepEqual(doc.Trailers, tc.trailers) {
				t.Fatalf("Trailers = %#v, want %#v", doc.Trailers, tc.trailers)
			}
		})
	}
}

func TestParseCRLF(t *testing.T) {
	doc := Parse("subject\r\n\r\nAssisted-by: a:b\r\n")
	if !doc.CRLF || !doc.TrailingEOL {
		t.Fatalf("CRLF=%v TrailingEOL=%v", doc.CRLF, doc.TrailingEOL)
	}
	if got := doc.Body(); got != "subject" {
		t.Fatalf("Body() = %q", got)
	}
	if len(doc.Trailers) != 1 || doc.Trailers[0].Value != "a:b" {
		t.Fatalf("Trailers = %#v", doc.Trailers)
	}
}

func TestAppend(t *testing.T) {
	cases := []struct {
		name    string
		input   string
		extra   []Trailer
		want    string
		added   []Trailer
		skipped []Trailer
	}{
		{
			name:  "empty description",
			input: "",
			extra: []Trailer{{"Assisted-by", "opencode:m"}},
			want:  "Assisted-by: opencode:m",
			added: []Trailer{{"Assisted-by", "opencode:m"}},
		},
		{
			name:  "body without trailers gets a blank line",
			input: "subject\n",
			extra: []Trailer{{"Assisted-by", "opencode:m"}},
			want:  "subject\n\nAssisted-by: opencode:m\n",
			added: []Trailer{{"Assisted-by", "opencode:m"}},
		},
		{
			name:  "existing block grows",
			input: "subject\n\nSigned-off-by: Human <h@example.com>\n",
			extra: []Trailer{{"Assisted-by", "opencode:m"}},
			want:  "subject\n\nSigned-off-by: Human <h@example.com>\nAssisted-by: opencode:m\n",
			added: []Trailer{{"Assisted-by", "opencode:m"}},
		},
		{
			name:    "exact duplicate is skipped",
			input:   "subject\n\nAssisted-by: opencode:m\n",
			extra:   []Trailer{{"Assisted-by", "opencode:m"}},
			want:    "subject\n\nAssisted-by: opencode:m\n",
			skipped: []Trailer{{"Assisted-by", "opencode:m"}},
		},
		{
			name:  "distinct multi-valued trailer is added",
			input: "Assisted-by: claude:opus\n",
			extra: []Trailer{{"Assisted-by", "opencode:m"}},
			want:  "Assisted-by: claude:opus\nAssisted-by: opencode:m\n",
			added: []Trailer{{"Assisted-by", "opencode:m"}},
		},
		{
			name:    "single-valued trailer keeps its first value",
			input:   "Session-Id: ses_old\n",
			extra:   []Trailer{{"Session-Id", "ses_new"}},
			want:    "Session-Id: ses_old\n",
			skipped: []Trailer{{"Session-Id", "ses_new"}},
		},
		{
			name:    "key comparison ignores case",
			input:   "assisted-by: opencode:m\n",
			extra:   []Trailer{{"Assisted-by", "opencode:m"}},
			want:    "assisted-by: opencode:m\n",
			skipped: []Trailer{{"Assisted-by", "opencode:m"}},
		},
		{
			name:    "duplicates inside extra collapse",
			input:   "",
			extra:   []Trailer{{"Assisted-by", "a:b"}, {"Assisted-by", "a:b"}},
			want:    "Assisted-by: a:b",
			added:   []Trailer{{"Assisted-by", "a:b"}},
			skipped: []Trailer{{"Assisted-by", "a:b"}},
		},
		{
			name:  "trailing blank line keeps its shape",
			input: "subject\n\nAssisted-by: a:b\n\n",
			extra: []Trailer{{"Session-Id", "ses_1"}},
			want:  "subject\n\nAssisted-by: a:b\nSession-Id: ses_1\n\n",
			added: []Trailer{{"Session-Id", "ses_1"}},
		},
		{
			name:  "crlf is preserved",
			input: "subject\r\n\r\nAssisted-by: a:b\r\n",
			extra: []Trailer{{"Session-Id", "ses_1"}},
			want:  "subject\r\n\r\nAssisted-by: a:b\r\nSession-Id: ses_1\r\n",
			added: []Trailer{{"Session-Id", "ses_1"}},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, added, skipped := Parse(tc.input).Append(tc.extra)
			if got != tc.want {
				t.Fatalf("Append() = %q, want %q", got, tc.want)
			}
			if !reflect.DeepEqual(added, tc.added) {
				t.Fatalf("added = %#v, want %#v", added, tc.added)
			}
			if !reflect.DeepEqual(skipped, tc.skipped) {
				t.Fatalf("skipped = %#v, want %#v", skipped, tc.skipped)
			}
		})
	}
}

func TestAppendIsIdempotent(t *testing.T) {
	extra := []Trailer{
		{"Assisted-by", "opencode:model"},
		{"Session-Id", "ses_1"},
		{"Harness", "opencode"},
		{"Model", "model"},
	}
	first, added, _ := Parse("subject\n").Append(extra)
	if len(added) != len(extra) {
		t.Fatalf("first run added %d trailers, want %d", len(added), len(extra))
	}
	second, added, skipped := Parse(first).Append(extra)
	if second != first {
		t.Fatalf("second run changed the description:\n%q\n%q", first, second)
	}
	if len(added) != 0 {
		t.Fatalf("second run added %#v", added)
	}
	if len(skipped) != len(extra) {
		t.Fatalf("second run skipped %d trailers, want %d", len(skipped), len(extra))
	}
}

func TestParseKeyValue(t *testing.T) {
	got, err := ParseKeyValue("Reviewed-by=Human <h@example.com>")
	if err != nil {
		t.Fatal(err)
	}
	if got.Key != "Reviewed-by" || got.Value != "Human <h@example.com>" {
		t.Fatalf("got %#v", got)
	}
	for _, bad := range []string{"", "novalue", "=value", "key="} {
		if _, err := ParseKeyValue(bad); err == nil {
			t.Fatalf("ParseKeyValue(%q) accepted a malformed argument", bad)
		}
	}
}
