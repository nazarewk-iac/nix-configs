// Package iso8601 parses the arbitrary-precision ISO 8601 dates the certificate options carry.
//
// A missing component takes its lowest value, so `2026` means `2026-01-01T00:00:00Z`. See design
// § 5.6.
package iso8601

import (
	"fmt"
	"strings"
	"time"
)

// layouts lists the accepted forms, most precise first. Go's reference time is
// `2006-01-02T15:04:05Z07:00`.
var layouts = []string{
	"2006-01-02T15:04:05Z07:00",
	"2006-01-02T15:04:05",
	"2006-01-02T15:04",
	"2006-01-02",
	"2006-01",
	"2006",
}

// Parse reads one ISO 8601 value. A trailing `Z` is accepted on every form. A missing component
// takes its lowest value. The result is always UTC.
func Parse(value string) (time.Time, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return time.Time{}, fmt.Errorf("empty date")
	}

	// A trailing `Z` on a form without a time zone is the UTC marker. A form that already carries
	// `Z07:00` matches as-is.
	candidates := []string{trimmed}
	if strings.HasSuffix(trimmed, "Z") {
		candidates = append(candidates, strings.TrimSuffix(trimmed, "Z"))
	}

	for _, candidate := range candidates {
		for _, layout := range layouts {
			parsed, err := time.Parse(layout, candidate)
			if err == nil {
				return parsed.UTC(), nil
			}
		}
	}

	return time.Time{}, fmt.Errorf("cannot parse ISO 8601 date %q", value)
}

// Before reports whether the certificate `notBefore` date is older than the minimum generation
// date. A null minimum never triggers a regeneration.
func Before(notBefore time.Time, minGenerationDate *string) (bool, error) {
	if minGenerationDate == nil {
		return false, nil
	}
	minimum, err := Parse(*minGenerationDate)
	if err != nil {
		return false, err
	}
	return notBefore.Before(minimum), nil
}
