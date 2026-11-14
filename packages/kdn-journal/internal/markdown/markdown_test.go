package markdown_test

import (
	"reflect"
	"testing"

	"kdn-journal/internal/markdown"
)

func TestScanLineKinds(t *testing.T) {
	data := []byte("# Heading\n\nprose here\n- bullet\n| a | b |\n```\ncode\n```\n")
	lines := markdown.Scan(data)

	want := []markdown.Kind{
		markdown.KindHeading,
		markdown.KindBlank,
		markdown.KindProse,
		markdown.KindBullet,
		markdown.KindTable,
		markdown.KindFence,
		markdown.KindFence,
		markdown.KindFence,
	}
	if len(lines) != len(want) {
		t.Fatalf("Scan returned %d lines, want %d: %+v", len(lines), len(want), lines)
	}
	for i, kind := range want {
		if lines[i].Kind != kind {
			t.Errorf("line %d (%q) Kind = %v, want %v", i+1, lines[i].Raw, lines[i].Kind, kind)
		}
		if lines[i].Number != i+1 {
			t.Errorf("line %d Number = %d, want %d", i+1, lines[i].Number, i+1)
		}
	}
}

func TestScanTrailingNewlineDropped(t *testing.T) {
	if got := len(markdown.Scan([]byte("a\n"))); got != 1 {
		t.Errorf("Scan(\"a\\n\") returned %d lines, want 1", got)
	}
	if got := len(markdown.Scan([]byte("a"))); got != 1 {
		t.Errorf("Scan(\"a\") returned %d lines, want 1", got)
	}
	if got := len(markdown.Scan(nil)); got != 0 {
		t.Errorf("Scan(nil) returned %d lines, want 0", got)
	}
}

func TestScanHeadings(t *testing.T) {
	data := []byte("# One\n## Two\n### Three ###\n###### Six\n####### Seven\n")
	lines := markdown.Scan(data)

	wantLevels := []int{1, 2, 3, 6, 0}
	wantTexts := []string{"One", "Two", "Three", "Six", ""}
	for i, want := range wantLevels {
		if want == 0 {
			if lines[i].Kind != markdown.KindProse {
				t.Errorf("line %d Kind = %v, want prose for 7 hashes", i+1, lines[i].Kind)
			}
			continue
		}
		if lines[i].Kind != markdown.KindHeading {
			t.Errorf("line %d Kind = %v, want heading", i+1, lines[i].Kind)
			continue
		}
		if lines[i].Level != want {
			t.Errorf("line %d Level = %d, want %d", i+1, lines[i].Level, want)
		}
		if lines[i].Text != wantTexts[i] {
			t.Errorf("line %d Text = %q, want %q", i+1, lines[i].Text, wantTexts[i])
		}
	}
}

func TestScanIndentedHeading(t *testing.T) {
	lines := markdown.Scan([]byte("  ## Indented\n"))
	if len(lines) != 1 || lines[0].Kind != markdown.KindHeading {
		t.Fatalf("lines = %+v, want one heading", lines)
	}
	if lines[0].Text != "Indented" || lines[0].Indent != 2 {
		t.Errorf("Text = %q Indent = %d, want %q and 2", lines[0].Text, lines[0].Indent, "Indented")
	}
}

func TestScanFencedCodeHidesStructures(t *testing.T) {
	data := []byte("# real heading\n\n```\n# fake heading\n- fake bullet\n| a | b |\n```\n\n## after\n")
	lines := markdown.Scan(data)

	for _, line := range lines {
		if line.Kind == markdown.KindHeading && line.Text == "fake heading" {
			t.Fatal("a heading inside a fence was reported as KindHeading")
		}
		if line.Kind == markdown.KindBullet {
			t.Fatalf("bullet %q inside a fence was reported as KindBullet", line.Text)
		}
		if line.Kind == markdown.KindTable {
			t.Fatalf("table row %q inside a fence was reported as KindTable", line.Text)
		}
	}

	headings := markdown.Headings(lines)
	if len(headings) != 2 {
		t.Fatalf("Headings = %+v, want 2", headings)
	}
	if headings[0].Text != "real heading" || headings[1].Text != "after" {
		t.Errorf("Headings = %q, %q, want %q, %q", headings[0].Text, headings[1].Text, "real heading", "after")
	}
	if tables := markdown.Tables(lines); len(tables) != 0 {
		t.Errorf("Tables = %+v, want none", tables)
	}
}

func TestScanTildeFence(t *testing.T) {
	data := []byte("~~~text\n## not a heading\n~~~\n")
	lines := markdown.Scan(data)
	for i, line := range lines {
		if line.Kind != markdown.KindFence {
			t.Errorf("line %d Kind = %v, want fence", i+1, line.Kind)
		}
	}
	if len(markdown.Headings(lines)) != 0 {
		t.Error("Headings is non-empty for a tilde fence")
	}
}

func TestScanLongerFenceNeedsMatchingLength(t *testing.T) {
	data := []byte("````\ncode\n```\nstill code\n````\n# after\n")
	lines := markdown.Scan(data)
	for i := 0; i < 4; i++ {
		if lines[i].Kind != markdown.KindFence {
			t.Errorf("line %d Kind = %v, want fence", i+1, lines[i].Kind)
		}
	}
	if lines[5].Kind != markdown.KindHeading || lines[5].Text != "after" {
		t.Errorf("line 6 = %+v, want the heading %q", lines[5], "after")
	}
}

func TestScanUnclosedFence(t *testing.T) {
	data := []byte("## head\n```\n# inside\n- bullet\n")
	lines := markdown.Scan(data)
	if lines[0].Kind != markdown.KindHeading {
		t.Fatalf("line 1 Kind = %v, want heading", lines[0].Kind)
	}
	for i := 1; i < len(lines); i++ {
		if lines[i].Kind != markdown.KindFence {
			t.Errorf("line %d Kind = %v, want fence", i+1, lines[i].Kind)
		}
	}
}

func TestScanBullets(t *testing.T) {
	data := []byte("- dash\n* star\n+ plus\n1. dot\n2) paren\n- [ ] open\n- [x] done\n- [X] big\n  - nested\n- [ ]\n")
	lines := markdown.Scan(data)

	if len(lines) != 10 {
		t.Fatalf("Scan returned %d lines, want 10", len(lines))
	}
	wantMarkers := []string{"-", "*", "+", "1.", "2)", "-", "-", "-", "-", "-"}
	wantTexts := []string{"dash", "star", "plus", "dot", "paren", "open", "done", "big", "nested", ""}
	wantCheckbox := []int{-1, -1, -1, -1, -1, 0, 1, 1, -1, 0}
	for i, line := range lines {
		if line.Kind != markdown.KindBullet {
			t.Errorf("line %d Kind = %v, want bullet", i+1, line.Kind)
			continue
		}
		if line.Marker != wantMarkers[i] {
			t.Errorf("line %d Marker = %q, want %q", i+1, line.Marker, wantMarkers[i])
		}
		if line.Text != wantTexts[i] {
			t.Errorf("line %d Text = %q, want %q", i+1, line.Text, wantTexts[i])
		}
		if line.Checkbox != wantCheckbox[i] {
			t.Errorf("line %d Checkbox = %d, want %d", i+1, line.Checkbox, wantCheckbox[i])
		}
	}
	if lines[8].Indent != 2 {
		t.Errorf("nested Indent = %d, want 2", lines[8].Indent)
	}
}

func TestScanTabIndentIsFourSpaces(t *testing.T) {
	lines := markdown.Scan([]byte("\t- item\n"))
	if len(lines) != 1 || lines[0].Kind != markdown.KindBullet {
		t.Fatalf("lines = %+v, want one bullet", lines)
	}
	if lines[0].Indent != 4 {
		t.Errorf("Indent = %d, want 4", lines[0].Indent)
	}
}

func TestScanPipeProseIsTableLike(t *testing.T) {
	lines := markdown.Scan([]byte("see | this\n"))
	if len(lines) != 1 || lines[0].Kind != markdown.KindTable {
		t.Fatalf("lines = %+v, want one table-like line", lines)
	}
	if tables := markdown.Tables(lines); len(tables) != 0 {
		t.Errorf("Tables = %+v, want none for a lone row", tables)
	}
}

func TestTablesGroupingAndRejection(t *testing.T) {
	data := []byte("| a | b |\n| --- | ---: |\n| 1 | 2 |\n| 3 | 4 |\n\n| no | separator |\n| just | rows |\n\n| single |\n")
	tables := markdown.Tables(markdown.Scan(data))

	if len(tables) != 1 {
		t.Fatalf("Tables returned %d tables, want 1", len(tables))
	}
	table := tables[0]
	if len(table) != 3 {
		t.Fatalf("table has %d rows, want 3 (header and two body rows)", len(table))
	}
	if want := []string{"a", "b"}; !reflect.DeepEqual(table[0].Cells, want) {
		t.Errorf("header cells = %v, want %v", table[0].Cells, want)
	}
	if want := []string{"1", "2"}; !reflect.DeepEqual(table[1].Cells, want) {
		t.Errorf("row 1 cells = %v, want %v", table[1].Cells, want)
	}
	if want := []string{"3", "4"}; !reflect.DeepEqual(table[2].Cells, want) {
		t.Errorf("row 2 cells = %v, want %v", table[2].Cells, want)
	}
}

func TestTablesSeparatorVariants(t *testing.T) {
	data := []byte("| a | b | c |\n|:---|:---:|---:|\n| 1 | 2 | 3 |\n")
	tables := markdown.Tables(markdown.Scan(data))
	if len(tables) != 1 {
		t.Fatalf("Tables returned %d tables, want 1", len(tables))
	}
	if len(tables[0]) != 2 {
		t.Fatalf("table has %d rows, want 2", len(tables[0]))
	}

	short := []byte("| a | b |\n|:--|--:|\n| 1 | 2 |\n")
	if tables := markdown.Tables(markdown.Scan(short)); len(tables) != 1 {
		t.Errorf("Tables = %+v, want one table for a two-dash separator", tables)
	}
}

func TestTablesWithoutPipesOutsideSeparator(t *testing.T) {
	data := []byte("| a | b |\n| not | a separator |\n| 1 | 2 |\n")
	if tables := markdown.Tables(markdown.Scan(data)); len(tables) != 0 {
		t.Errorf("Tables = %+v, want none", tables)
	}
}

func TestHeadingsHelper(t *testing.T) {
	data := []byte("# first\n\nprose\n\n### third\n\n## second\n")
	headings := markdown.Headings(markdown.Scan(data))

	want := []struct {
		level int
		text  string
	}{
		{level: 1, text: "first"},
		{level: 3, text: "third"},
		{level: 2, text: "second"},
	}
	if len(headings) != len(want) {
		t.Fatalf("Headings returned %d, want %d", len(headings), len(want))
	}
	for i, w := range want {
		if headings[i].Level != w.level || headings[i].Text != w.text {
			t.Errorf("heading %d = (%d, %q), want (%d, %q)", i, headings[i].Level, headings[i].Text, w.level, w.text)
		}
	}
}

func TestScanBlankAndProseIndent(t *testing.T) {
	lines := markdown.Scan([]byte("   \n    indented prose\n"))
	if len(lines) != 2 {
		t.Fatalf("Scan returned %d lines, want 2", len(lines))
	}
	if lines[0].Kind != markdown.KindBlank {
		t.Errorf("line 1 Kind = %v, want blank", lines[0].Kind)
	}
	if lines[1].Kind != markdown.KindProse {
		t.Errorf("line 2 Kind = %v, want prose", lines[1].Kind)
	}
	if lines[1].Indent != 4 {
		t.Errorf("line 2 Indent = %d, want 4", lines[1].Indent)
	}
}

func TestScanCRLF(t *testing.T) {
	lines := markdown.Scan([]byte("## H\r\n\r\ntext\r\n"))
	if len(lines) != 3 {
		t.Fatalf("Scan returned %d lines, want 3", len(lines))
	}
	if lines[0].Kind != markdown.KindHeading || lines[0].Text != "H" {
		t.Errorf("line 1 = %+v, want heading %q", lines[0], "H")
	}
	if lines[1].Kind != markdown.KindBlank {
		t.Errorf("line 2 Kind = %v, want blank", lines[1].Kind)
	}
	if lines[2].Kind != markdown.KindProse || lines[2].Text != "text" {
		t.Errorf("line 3 = %+v, want prose %q", lines[2], "text")
	}
}
