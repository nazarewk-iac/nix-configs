// Package combine models one joined output: a virtual sink that plays the same audio to several
// physical sinks.
//
// A joined output is a native PipeWire `libpipewire-module-combine-stream` instance. Every fact
// about it is a property on the sink that the module creates, so the module, the sink and the
// description die together:
//
//	kdn.audio.combined=yes            marks a sink that this tool created
//	kdn.audio.members="a,b"           the sink names it plays to
//	kdn.audio.profile=<name>          the profile that created it, when one did
//	kdn.audio.created-at=<RFC 3339>   when it was created
package combine

import (
	"fmt"
	"strings"
	"time"
	"unicode"

	"kdn-audio/internal/pipewire"
)

// Property keys, re-exported for readability at the call sites.
const (
	PropCombined        = pipewire.PropCombined
	PropMembers         = pipewire.PropMembers
	PropProfile         = pipewire.PropProfile
	PropCreated         = pipewire.PropCreated
	PropPreviousDefault = pipewire.PropPreviousDefault
)

// Group is one joined output.
type Group struct {
	SinkName        string
	Title           string
	Members         []string
	Profile         string
	PreviousDefault string
	CreatedAt       time.Time
	Default         bool
}

// IsCombined reports whether the sink is a joined output that this tool created.
func IsCombined(sink pipewire.Sink) bool {
	return sink.Props[PropCombined] == "yes"
}

// FromSinks returns every joined output.
func FromSinks(sinks []pipewire.Sink, defaultSink string) []Group {
	groups := []Group{}
	for _, sink := range sinks {
		if !IsCombined(sink) {
			continue
		}
		group := Group{
			SinkName:        sink.Name,
			Title:           sink.Description,
			Profile:         sink.Props[PropProfile],
			PreviousDefault: sink.Props[PropPreviousDefault],
			Default:         sink.Name == defaultSink,
		}
		if members := sink.Props[PropMembers]; members != "" {
			for _, member := range strings.Split(members, ",") {
				if member = strings.TrimSpace(member); member != "" {
					group.Members = append(group.Members, member)
				}
			}
		}
		if created := sink.Props[PropCreated]; created != "" {
			if parsed, err := time.Parse(time.RFC3339, created); err == nil {
				group.CreatedAt = parsed
			}
		}
		groups = append(groups, group)
	}
	return groups
}

// Title builds the default name of a joined output from its members.
func Title(members []pipewire.Sink) string {
	names := make([]string, 0, len(members))
	for _, member := range members {
		names = append(names, member.Description)
	}
	return strings.Join(names, " + ")
}

// Slug reduces a title to the character set that a node name accepts.
func Slug(title string) string {
	var builder strings.Builder
	lastUnderscore := true
	for _, r := range strings.ToLower(title) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			builder.WriteRune(r)
			lastUnderscore = false
			continue
		}
		if !lastUnderscore {
			builder.WriteByte('_')
			lastUnderscore = true
		}
	}
	slug := strings.Trim(builder.String(), "_")
	if slug == "" {
		slug = "output"
	}
	if len(slug) > 48 {
		slug = strings.Trim(slug[:48], "_")
	}
	return slug
}

// SinkName builds the node name of a joined output from its title.
func SinkName(title string) string {
	return "combined_" + Slug(title)
}

// ValidateTitle rejects a title that cannot pass through the module-argument syntax.
//
// The title becomes a quoted SPA JSON string inside a single pw-cli command, so a quote or a
// backslash would break that syntax. The tool refuses such a name instead of guessing an escape.
func ValidateTitle(title string) error {
	if strings.TrimSpace(title) == "" {
		return fmt.Errorf("the name must not be empty")
	}
	if len([]rune(title)) > 64 {
		return fmt.Errorf("the name is longer than 64 characters")
	}
	for _, r := range title {
		switch {
		case r == '\'' || r == '"':
			return fmt.Errorf("the name must not contain a quote")
		case r == '\\':
			return fmt.Errorf("the name must not contain a backslash")
		case unicode.IsControl(r):
			return fmt.Errorf("the name must not contain control characters")
		}
	}
	return nil
}

// MemberNames returns the node names of the members.
func MemberNames(members []pipewire.Sink) []string {
	names := make([]string, 0, len(members))
	for _, member := range members {
		names = append(names, member.Name)
	}
	return names
}

// MissingMembers returns the members that no longer exist as sinks.
func MissingMembers(group Group, sinks []pipewire.Sink) []string {
	present := map[string]bool{}
	for _, sink := range sinks {
		present[sink.Name] = true
	}
	missing := []string{}
	for _, member := range group.Members {
		if !present[member] {
			missing = append(missing, member)
		}
	}
	return missing
}
