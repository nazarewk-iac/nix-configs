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
	"strings"

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

// SSHSigner generates an ed25519 key and signs an SSH user or host certificate. It is
// `smallstep.SSHSigner`. `apply` reaches it for a leaf whose `type` is `ssh-user` or `ssh-host`;
// the TLS `Signer` refuses those. See sub-task 008.
type SSHSigner interface {
	GenerateSSHKey(keyOut string) error
	SignSSH(req smallstep.SSHCertRequest) error
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
	// SSHSigner generates an ed25519 key and signs SSH leaves. It may be nil when the caller knows
	// no `ssh-user` or `ssh-host` leaf is declared; an SSH leaf with a nil SSHSigner is a hard error.
	SSHSigner SSHSigner
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

// sshValidityDefault is the OpenSSH validity interval `apply` asks the SSH CA to sign. `apply` is
// the automation path, so the interval is the long automation class of design § 7.0, not the short
// interactive one `ssh login` uses. The exact value is a security choice for the task owner; this
// default is what makes a declared `ssh-host` leaf re-signable without an interactive tool.
const sshValidityDefault = "+30d"

// generateOne generates one certificate: key, sign, write the public cert, SOPS-encrypt the key.
//
// The private key is written plain to a temporary file, SOPS-encrypted next to the public
// certificate, and the temporary file is removed. So no plaintext key survives the call.
//
// A `tls-server` or `tls-client` leaf goes through `generateTLS`. An `ssh-user` or `ssh-host` leaf
// goes through `generateSSH`. See sub-task 008.
func generateOne(deps Deps, ca decl.CA, cert decl.Cert, certAbs string, keyAbs string) error {
	if cert.Type == "ssh-user" || cert.Type == "ssh-host" {
		return generateSSH(deps, ca, cert, certAbs, keyAbs)
	}
	return generateTLS(deps, ca, cert, certAbs, keyAbs)
}

// sshDecryptedCA decrypts the CA key into the temporary directory `tmpDir` and returns its plain
// path. Both the TLS and the SSH path need it; the SSH sign reads the private key directly and needs
// no `ca.json`.
func sshDecryptedCA(deps Deps, ca decl.CA, tmpDir string) (string, error) {
	caKeyAbs := deps.absPath(filepath.Join(ca.Directory, ca.KeyFile+".sops"))
	caKeyPlain := filepath.Join(tmpDir, "ca.key")
	if err := deps.Decryptor.Decrypt(caKeyAbs, caKeyPlain); err != nil {
		return "", err
	}
	return caKeyPlain, nil
}

// generateSSH signs an `ssh-user` or `ssh-host` leaf with the SSH CA using the OpenSSH-native
// `ssh-keygen` path that `ssh login` already proves.
//
// The leaf key must be `managed`: `ssh login` owns the interactive `external` case, and `apply`
// generates the key here so the private key can be SOPS-encrypted the same way a TLS leaf's is. The
// declared CA must sign SSH (`ssh = true`), exactly as `ssh login` requires.
func generateSSH(deps Deps, ca decl.CA, cert decl.Cert, certAbs string, keyAbs string) error {
	if !ca.SSH {
		return fmt.Errorf("ssh leaf %q: CA %q does not sign SSH certificates (`ssh = true` is not set)", cert.Name, ca.Name)
	}
	if cert.KeySource != "managed" {
		return fmt.Errorf("ssh leaf %q has keySource %q, want managed: `apply` generates and signs a managed SSH key; an external SSH key is issued by `kdn-certs ssh login`", cert.Name, cert.KeySource)
	}
	if deps.SSHSigner == nil {
		return fmt.Errorf("ssh leaf %q: no SSH signer is wired into generate.Deps", cert.Name)
	}

	if err := os.MkdirAll(filepath.Dir(certAbs), 0o755); err != nil {
		return fmt.Errorf("create %s: %w", filepath.Dir(certAbs), err)
	}

	tmpDir, err := os.MkdirTemp("", "kdn-certs-")
	if err != nil {
		return fmt.Errorf("create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	caKeyPlain, err := sshDecryptedCA(deps, ca, tmpDir)
	if err != nil {
		return err
	}

	// The leaf key: an ed25519 pair at `<tmpDir>/leaf.key` and `.pub`. `ssh-keygen -s` writes the
	// certificate at `<tmpDir>/leaf.key-cert.pub`.
	leafKeyPlain := filepath.Join(tmpDir, "leaf.key")
	if err := deps.SSHSigner.GenerateSSHKey(leafKeyPlain); err != nil {
		return err
	}

	req := smallstep.SSHCertRequest{
		KeyID:      cert.CommonName,
		Principals: cert.Principals,
		Validity:   sshValidityDefault,
		Host:       cert.Type == "ssh-host",
		PubKeyPath: leafKeyPlain + ".pub",
		CAKeyPath:  caKeyPlain,
	}
	if err := deps.SSHSigner.SignSSH(req); err != nil {
		return err
	}

	// Move the signed certificate from the temporary directory to the declared `<certFile>` path.
	signedCert := strings.TrimSuffix(leafKeyPlain+".pub", ".pub") + "-cert.pub"
	if err := moveFile(signedCert, certAbs); err != nil {
		return err
	}

	if err := deps.Encryptor.Encrypt(leafKeyPlain, keyAbs); err != nil {
		return err
	}

	return nil
}

// moveFile moves `src` to `dst`, across filesystems if needed. The temporary directory and the tree
// may live on different mounts, so a plain `os.Rename` can fail with EXDEV.
func moveFile(src, dst string) error {
	if err := os.Rename(src, dst); err == nil {
		return nil
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return fmt.Errorf("read %s: %w", src, err)
	}
	if err := os.WriteFile(dst, data, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", dst, err)
	}
	return os.Remove(src)
}

// generateTLS signs a `tls-server` or `tls-client` leaf with `step`.
func generateTLS(deps Deps, ca decl.CA, cert decl.Cert, certAbs string, keyAbs string) error {
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
