// Package okfkind maps the five item kinds to the OKF concept types and their directories in the
// memory bundle. One table, so the writer, the reader and the applier cannot disagree.
package okfkind

import "strings"

// typeNames maps a pipeline kind to the OKF type name.
var typeNames = map[string]string{
	"decision":   "Decision",
	"runbook":    "Runbook",
	"pitfall":    "Pitfall",
	"preference": "Preference",
	"fact":       "Fact",
}

// dirs maps a pipeline kind to the bundle directory that holds it.
var dirs = map[string]string{
	"decision":   "decisions",
	"runbook":    "runbooks",
	"pitfall":    "pitfalls",
	"preference": "preferences",
	"fact":       "facts",
}

// KindOfType maps an OKF type name back to a pipeline kind.
var kindOfType = func() map[string]string {
	out := make(map[string]string, len(typeNames))
	for kind, name := range typeNames {
		out[strings.ToLower(name)] = kind
	}
	return out
}()

// TypeName returns the OKF type of a kind, or "Fact" for an unknown kind.
func TypeName(kind string) string {
	if name, ok := typeNames[strings.ToLower(kind)]; ok {
		return name
	}
	return "Fact"
}

// Kind returns the pipeline kind of an OKF type, or the lowercased type.
func Kind(typeName string) string {
	if kind, ok := kindOfType[strings.ToLower(strings.TrimSpace(typeName))]; ok {
		return kind
	}
	return strings.ToLower(strings.TrimSpace(typeName))
}

// Dir returns the bundle directory of a kind, or "facts" for an unknown kind.
func Dir(kind string) string {
	if dir, ok := dirs[strings.ToLower(kind)]; ok {
		return dir
	}
	return "facts"
}
