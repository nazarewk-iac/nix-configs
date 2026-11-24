package combine

import (
	"reflect"
	"strings"
	"testing"

	"kdn-audio/internal/pipewire"
)

func TestValidateTitle(t *testing.T) {
	for _, valid := range []string{"Both Ears", "Earmuffs + JBL", "Oams (desk)", "zażółć"} {
		if err := ValidateTitle(valid); err != nil {
			t.Errorf("ValidateTitle(%q) = %v, want nil", valid, err)
		}
	}
	for _, invalid := range []string{"", "   ", `Both "Ears"`, "Both 'Ears'", `back\slash`, "line\nbreak"} {
		if err := ValidateTitle(invalid); err == nil {
			t.Errorf("ValidateTitle(%q) = nil, want an error", invalid)
		}
	}
	if err := ValidateTitle(strings.Repeat("a", 65)); err == nil {
		t.Error("ValidateTitle accepted 65 characters")
	}
}

func TestSlug(t *testing.T) {
	cases := map[string]string{
		"Both Ears":         "both_ears",
		"Earmuffs + JBL":    "earmuffs_jbl",
		"  weird__name  ":   "weird_name",
		"Oams (desk)":       "oams_desk",
		"":                  "output",
		"___":               "output",
		"Zażółć gęślą jaźń": "za_g_l_ja",
	}
	for title, want := range cases {
		if got := Slug(title); got != want {
			t.Errorf("Slug(%q) = %q, want %q", title, got, want)
		}
	}
	if got := SinkName("Both Ears"); got != "combined_both_ears" {
		t.Errorf("SinkName = %q", got)
	}
	long := Slug(strings.Repeat("ab ", 40))
	if len(long) > 48 {
		t.Errorf("Slug kept %d characters, want at most 48", len(long))
	}
}

func TestFromSinks(t *testing.T) {
	sinks := []pipewire.Sink{
		{Name: "combined_both", Description: "Both Ears", Props: map[string]string{
			PropCombined:        "yes",
			PropMembers:         "zz_a,zz_b",
			PropProfile:         "both",
			PropPreviousDefault: "alsa_output.x",
			PropCreated:         "2026-11-24T12:00:00Z",
		}},
		{Name: "alsa_output.x", Description: "Speakers"},
	}
	groups := FromSinks(sinks, "combined_both")
	if len(groups) != 1 {
		t.Fatalf("got %d groups, want 1", len(groups))
	}
	group := groups[0]
	if group.Title != "Both Ears" || group.SinkName != "combined_both" {
		t.Errorf("group = %+v", group)
	}
	if !reflect.DeepEqual(group.Members, []string{"zz_a", "zz_b"}) {
		t.Errorf("members = %v", group.Members)
	}
	if group.Profile != "both" {
		t.Errorf("profile = %q", group.Profile)
	}
	if group.PreviousDefault != "alsa_output.x" {
		t.Errorf("previous default = %q", group.PreviousDefault)
	}
	if !group.Default {
		t.Error("group is not marked default")
	}
	if group.CreatedAt.IsZero() {
		t.Error("created-at was not parsed")
	}
	if !IsCombined(sinks[0]) || IsCombined(sinks[1]) {
		t.Error("IsCombined misclassifies a sink")
	}
}

func TestMissingMembers(t *testing.T) {
	group := Group{Members: []string{"a", "b"}}
	missing := MissingMembers(group, []pipewire.Sink{{Name: "a"}})
	if !reflect.DeepEqual(missing, []string{"b"}) {
		t.Errorf("missing = %v", missing)
	}
}

func TestTitle(t *testing.T) {
	title := Title([]pipewire.Sink{{Description: "Earmuffs"}, {Description: "JBL"}})
	if title != "Earmuffs + JBL" {
		t.Errorf("Title = %q", title)
	}
}

func TestMemberNames(t *testing.T) {
	names := MemberNames([]pipewire.Sink{{Name: "a"}, {Name: "b"}})
	if !reflect.DeepEqual(names, []string{"a", "b"}) {
		t.Errorf("MemberNames = %v", names)
	}
}
