// Package generate drives the per-certificate generation loop.
//
// It walks the declarations, merges the CA graph, sorts it topologically, and for each leaf decides
// whether the certificate must be regenerated. A regeneration generates a key (when
// `keySource = "managed"`), signs the public certificate with `step`, and SOPS-encrypts the private
// key next to it. See design § 5.7 and § 6.
//
// Every side effect goes through an interface, so the loop is testable with no `step` binary, no
// `sops` binary and no CA. The test CA of design § 8.1 injects the real binaries against a
// temporary unattended CA.
package generate

import (
	"fmt"
	"os"
	"path/filepath"

	"kdn-certs/internal/certinfo"
	"kdn-certs/internal/decl"
	"kdn-certs/internal/dedup"
	"kdn-certs/internal/mismatch"
	"kdn-certs/internal/smallstep"
)

// Signer generates a key and signs a leaf. It is `smallstep.Signer`.
type Signer interface {
	GenerateKey(keyOut string) error
	SignLeaf(req smallstep.LeafRequest) error
}

// Decryptor decrypts a SOPS key file. It is `sops.Decryptor`.
type Decryptor interface {
	Decrypt(sopsFile string, dest string) error
}

// Encryptor encrypts a plaintext key to a raw/binary SOPS file. It is `sops.Encryptor`.
type Encryptor interface {
	Encrypt(plainFile string, sopsFile string) error
}

// Deps holds the side-effect implementations and the tree root.
type Deps struct {
	// Root is the tree root the repo-relative `directory` values resolve against.
	Root string
	// Signer generates keys and signs leaves.
	Signer Signer
	// Decryptor decrypts an `external` CA or leaf key.
	Decryptor Decryptor
	// Encryptor SOPS-encrypts a managed private key.
	Encryptor Encryptor
	// Force regenerates every certificate, whatever the mismatch test says.
	Force bool
	// DryRun prints the plan and changes nothing.
	DryRun bool
	// Logf receives one line per action.
	Logf func(format string, args ...any)
}

// Action is one decision the loop made for one certificate.
type Action struct {
	// Name is the certificate name.
	Name string `json:"name"`
	// CA is the signing CA name.
	CA string `json:"ca"`
	// Type is the certificate kind.
	Type string `json:"type"`
	// CertPath is the repo-relative public certificate path.
	CertPath string `json:"certPath"`
	// Reason is why the certificate is generated, or empty when it is current.
	Reason mismatch.Reason `json:"reason"`
}

// Result is the outcome of one loop run.
type Result struct {
	// Actions holds one entry per certificate, in declaration order.
	Actions []Action
	// Generated counts the certificates that were (or would be) generated.
	Generated int
}

// absPath joins a repo-relative path onto the tree root.
func (d Deps) absPath(rel string) string {
	if filepath.IsAbs(rel) {
		return rel
	}
	return filepath.Join(d.Root, rel)
}

// Run walks the deduplicated certificates and generates each one that the mismatch test selects.
//
// `cas` is the merged CA graph. The order of `result` is the deterministic certificate order of
// `dedup.Result.Sorted`, so a second run with no change makes no write.
func Run(cas decl.CAs, result dedup.Result, deps Deps) (Result, error) {
	out := Result{}

	for _, cert := range result.Sorted() {
		ca, ok := cas[cert.CA]
		if !ok {
			return out, fmt.Errorf("certificate %q names CA %q, which is not declared", cert.Name, cert.CA)
		}

		certRel := filepath.Join(cert.Directory, cert.CertFile)
		certAbs := deps.absPath(certRel)
		keyRel := filepath.Join(cert.Directory, cert.KeyFile+".sops")
		keyAbs := deps.absPath(keyRel)

		existing, err := certinfo.Read(certAbs)
		if err != nil {
			return out, err
		}
		reason, err := mismatch.Decide(cert, existing, ca.CommonName, deps.Force)
		if err != nil {
			return out, err
		}

		out.Actions = append(out.Actions, Action{
			Name:     cert.Name,
			CA:       cert.CA,
			Type:     cert.Type,
			CertPath: certRel,
			Reason:   reason,
		})

		if reason == mismatch.ReasonNone {
			continue
		}
		out.Generated++

		if deps.DryRun {
			deps.Logf("would generate %s (%s) with CA %s: %s", cert.Name, cert.Type, cert.CA, reason)
			continue
		}

		if err := generateOne(deps, ca, cert, certAbs, keyAbs); err != nil {
			return out, err
		}
		deps.Logf("generated %s (%s) with CA %s: %s", cert.Name, cert.Type, cert.CA, reason)
	}

	return out, nil
}

// generateOne generates one certificate: key, sign, write the public cert, SOPS-encrypt the key.
//
// The private key is written plain to a temporary file, SOPS-encrypted next to the public
// certificate, and the temporary file is removed. So no plaintext key survives the call.
func generateOne(deps Deps, ca decl.CA, cert decl.Cert, certAbs string, keyAbs string) error {
	if err := os.MkdirAll(filepath.Dir(certAbs), 0o755); err != nil {
		return fmt.Errorf("create %s: %w", filepath.Dir(certAbs), err)
	}

	// The CA private key. It is always SOPS-sourced: `<directory>/<keyFile>.sops`. `sops` prompts
	// for the YubiKey touch inside the decrypt when the key is encrypted to YubiKey identities.
	caKeyAbs := deps.absPath(filepath.Join(ca.Directory, ca.KeyFile+".sops"))
	caCertAbs := deps.absPath(filepath.Join(ca.Directory, ca.CertFile))

	tmpDir, err := os.MkdirTemp("", "kdn-certs-")
	if err != nil {
		return fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	caKeyPlain := filepath.Join(tmpDir, "ca.key")
	if err := deps.Decryptor.Decrypt(caKeyAbs, caKeyPlain); err != nil {
		return err
	}

	// The leaf private key. `managed` generates it; `external` decrypts it from its own SOPS file.
	leafKeyPlain := filepath.Join(tmpDir, "leaf.key")
	switch cert.KeySource {
	case "managed":
		if err := deps.Signer.GenerateKey(leafKeyPlain); err != nil {
			return err
		}
	case "external":
		if err := deps.Decryptor.Decrypt(keyAbs, leafKeyPlain); err != nil {
			return err
		}
	default:
		return fmt.Errorf("certificate %q has keySource %q, want managed or external", cert.Name, cert.KeySource)
	}

	req := smallstep.LeafRequest{
		CommonName: cert.CommonName,
		SANs:       cert.SANs,
		Principals: cert.Principals,
		Type:       cert.Type,
		KeyPath:    leafKeyPlain,
		CertPath:   certAbs,
		CACertPath: caCertAbs,
		CAKeyPath:  caKeyPlain,
	}
	if err := deps.Signer.SignLeaf(req); err != nil {
		return err
	}

	// The private key is always SOPS-sourced on disk, whatever made it. A managed key is encrypted
	// now; an external key already has its committed SOPS file and is left in place.
	if cert.KeySource == "managed" {
		if err := deps.Encryptor.Encrypt(leafKeyPlain, keyAbs); err != nil {
			return err
		}
	}

	return nil
}
