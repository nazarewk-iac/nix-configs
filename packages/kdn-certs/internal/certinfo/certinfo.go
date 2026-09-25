// Package certinfo reads the two fields the rotation test needs from an existing certificate.
//
// The rotation test compares a certificate's own `notBefore` against the declared
// `minGenerationDate`, and its issuer common name against the declared CA common name. Both values
// come from the committed public certificate, so the read is pure Go and needs no `step` call and
// no network. See design § 5.7.
package certinfo

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"time"
)

// Info is the state of a certificate that is already on disk.
type Info struct {
	// NotBefore is the certificate's own not-before date.
	NotBefore time.Time
	// IssuerCN is the common name of the certificate issuer.
	IssuerCN string
}

// Read parses one PEM certificate and returns its not-before date and issuer common name.
//
// A missing file is not an error: the caller treats it as "no certificate yet". A file that holds
// no PEM block, or a PEM block that is not a certificate, is an error, so a corrupt file fails
// loudly instead of silently regenerating.
func Read(path string) (*Info, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read certificate %s: %w", path, err)
	}

	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("certificate %s holds no PEM block", path)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse certificate %s: %w", path, err)
	}

	return &Info{NotBefore: cert.NotBefore.UTC(), IssuerCN: cert.Issuer.CommonName}, nil
}
