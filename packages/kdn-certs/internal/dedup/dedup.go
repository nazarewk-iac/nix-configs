// Package dedup collapses the declarations of every target into one certificate set.
//
// The dedup key is `(ca, type, commonName, directory, certFile)`. Two declarations with one key are
// one certificate. The first wins, and a duplicate is reported. See design § 5.5.
package dedup

import (
	"sort"

	"kdn-certs/internal/decl"
)

// Result is the deduplicated certificate set plus the duplicates that were dropped.
type Result struct {
	// Certs is the kept certificate set, keyed by dedup key.
	Certs map[string]decl.Cert
	// Duplicates names each dropped declaration: the dedup key and the target it came from.
	Duplicates []Duplicate
}

// Duplicate is one dropped declaration.
type Duplicate struct {
	Key    string
	Target string
	Name   string
}

// Merge walks every target in order and keeps the first declaration of each dedup key.
func Merge(targets []decl.Target) Result {
	result := Result{Certs: map[string]decl.Cert{}}
	for _, target := range targets {
		names := make([]string, 0, len(target.Certs))
		for name := range target.Certs {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			cert := target.Certs[name]
			cert.Name = name
			key := cert.DedupKey()
			if _, ok := result.Certs[key]; ok {
				result.Duplicates = append(result.Duplicates, Duplicate{
					Key:    key,
					Target: target.Name,
					Name:   name,
				})
				continue
			}
			result.Certs[key] = cert
		}
	}
	return result
}

// Sorted returns the kept certificates in a deterministic order.
func (r Result) Sorted() []decl.Cert {
	keys := make([]string, 0, len(r.Certs))
	for key := range r.Certs {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	certs := make([]decl.Cert, 0, len(keys))
	for _, key := range keys {
		certs = append(certs, r.Certs[key])
	}
	return certs
}
