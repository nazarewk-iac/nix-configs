// Package mismatch decides whether a certificate must be regenerated.
//
// Three conditions trigger a regeneration: a stale `notBefore`, an issuer CN that does not match the
// declared CA, and `--force`. See design § 5.7.
package mismatch

import (
	"kdn-certs/internal/certinfo"
	"kdn-certs/internal/decl"
	"kdn-certs/internal/iso8601"
)

// Existing is the state of a certificate that is already on disk. It aliases `certinfo.Info`, so a
// reader of the public certificate feeds `Decide` with no conversion.
type Existing = certinfo.Info

// Reason names why a certificate must be regenerated.
type Reason string

const (
	// ReasonNone means the certificate is current.
	ReasonNone Reason = ""
	// ReasonStale means `notBefore` is older than `minGenerationDate`.
	ReasonStale Reason = "stale generation date"
	// ReasonIssuer means the issuer CN does not match the declared CA common name.
	ReasonIssuer Reason = "issuer mismatch"
	// ReasonForced means `--force` was set.
	ReasonForced Reason = "forced"
	// ReasonMissing means no certificate file exists yet.
	ReasonMissing Reason = "missing"
)

// Decide returns the regeneration reason for one certificate.
//
// `existing` is nil when no certificate file exists yet. `caCommonName` is the declared common name
// of the signing CA. `force` regenerates whatever the other tests say.
func Decide(cert decl.Cert, existing *Existing, caCommonName string, force bool) (Reason, error) {
	if force {
		return ReasonForced, nil
	}
	if existing == nil {
		return ReasonMissing, nil
	}
	stale, err := iso8601.Before(existing.NotBefore, cert.MinGenerationDate)
	if err != nil {
		return ReasonNone, err
	}
	if stale {
		return ReasonStale, nil
	}
	if existing.IssuerCN != caCommonName {
		return ReasonIssuer, nil
	}
	return ReasonNone, nil
}
