// Package textsim holds the deterministic lexical similarity that the pipeline uses instead of a
// model. Clustering must give the same answer on every run, so nothing here depends on map order.
package textsim

import (
	"sort"
	"strings"
	"unicode"
)

// Tokens splits text into lowercase alphanumeric words.
func Tokens(text string) []string {
	fields := strings.FieldsFunc(strings.ToLower(text), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
	tokens := make([]string, 0, len(fields))
	for _, field := range fields {
		if field == "" {
			continue
		}
		tokens = append(tokens, field)
	}
	return tokens
}

// Trigrams returns the set of lowercased word trigrams of text. A text with fewer than three
// words contributes its own words, so two two-word statements still compare.
func Trigrams(text string) map[string]struct{} {
	tokens := Tokens(text)
	grams := map[string]struct{}{}
	switch {
	case len(tokens) == 0:
		return grams
	case len(tokens) < 3:
		for _, token := range tokens {
			grams[token] = struct{}{}
		}
		return grams
	}
	for i := 0; i+3 <= len(tokens); i++ {
		grams[strings.Join(tokens[i:i+3], " ")] = struct{}{}
	}
	return grams
}

// Jaccard returns the Jaccard index of two sets.
func Jaccard(a, b map[string]struct{}) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	intersection := 0
	for gram := range a {
		if _, ok := b[gram]; ok {
			intersection++
		}
	}
	union := len(a) + len(b) - intersection
	if union == 0 {
		return 0
	}
	return float64(intersection) / float64(union)
}

// Similarity returns the Jaccard index of the word trigrams of two texts.
func Similarity(a, b string) float64 {
	return Jaccard(Trigrams(a), Trigrams(b))
}

// TagBonus is the score a shared tag adds.
const TagBonus = 0.1

// SimilarityWithTags adds a bonus when the two tag sets intersect, and caps the score at 1.
func SimilarityWithTags(a string, b string, tagsA []string, tagsB []string) float64 {
	score := Similarity(a, b)
	if TagsIntersect(tagsA, tagsB) {
		score += TagBonus
	}
	if score > 1 {
		score = 1
	}
	return score
}

// TagsIntersect reports whether the two tag lists share one lowercased tag.
func TagsIntersect(a []string, b []string) bool {
	seen := make(map[string]struct{}, len(a))
	for _, tag := range a {
		seen[strings.ToLower(strings.TrimSpace(tag))] = struct{}{}
	}
	for _, tag := range b {
		if _, ok := seen[strings.ToLower(strings.TrimSpace(tag))]; ok {
			return true
		}
	}
	return false
}

// NormalizeTags lowercases, trims, deduplicates and sorts a tag list.
func NormalizeTags(tags []string) []string {
	set := map[string]struct{}{}
	for _, tag := range tags {
		clean := strings.ToLower(strings.TrimSpace(tag))
		if clean == "" {
			continue
		}
		set[clean] = struct{}{}
	}
	out := make([]string, 0, len(set))
	for tag := range set {
		out = append(out, tag)
	}
	sort.Strings(out)
	return out
}

// Slug builds a lowercase hyphenated identifier of at most maxWords significant words.
func Slug(text string, maxWords int) string {
	tokens := Tokens(text)
	words := make([]string, 0, maxWords)
	for _, token := range tokens {
		if stopword[token] {
			continue
		}
		words = append(words, token)
		if len(words) >= maxWords {
			break
		}
	}
	return strings.Join(words, "-")
}

// stopword drops words that carry no meaning in an identifier.
var stopword = map[string]bool{
	"a": true, "an": true, "and": true, "are": true, "as": true, "at": true, "be": true,
	"by": true, "for": true, "from": true, "in": true, "into": true, "is": true, "it": true,
	"of": true, "on": true, "or": true, "that": true, "the": true, "then": true, "this": true,
	"to": true, "use": true, "when": true, "with": true,
}
