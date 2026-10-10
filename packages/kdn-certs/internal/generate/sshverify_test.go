package generate_test

// SSH certificate verification for acceptance 4, implemented with the Go standard library.
//
// The signed region of an OpenSSH certificate is defined by `cert_parse` in portable OpenSSH
// `sshkey.c`: everything from the start of the certificate blob up to the length prefix of the
// signature field — that is, `certtype || nonce || key || serial || type || key_id || principals ||
// valid_after || valid_before || critical_options || extensions || reserved || signature_key`.
// Verification is then a plain ECDSA or Ed25519 check of the trailing signature over that region,
// under the key embedded as `signature_key`.

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"math/big"
	"os"
	"strings"
	"testing"
)

type sshReader struct {
	buf []byte
	err error
}

func (r *sshReader) take(n int) []byte {
	if r.err != nil {
		return nil
	}
	if len(r.buf) < n {
		r.err = errors.New("truncated OpenSSH certificate blob")
		return nil
	}
	v := r.buf[:n]
	r.buf = r.buf[n:]
	return v
}

func (r *sshReader) str() []byte {
	n := binaryBigEndian(r.take(4))
	return r.take(int(n))
}

func binaryBigEndian(b []byte) uint64 {
	var v uint64
	for _, x := range b {
		v = v<<8 | uint64(x)
	}
	return v
}

// sshCertB64Field returns the decoded base64 field of the first line of the certificate file.
func sshCertB64Field(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	fields := strings.Fields(string(raw))
	if len(fields) < 2 {
		t.Fatalf("%s is not an OpenSSH certificate line", path)
	}
	blob, err := base64.StdEncoding.DecodeString(fields[1])
	if err != nil {
		t.Fatalf("%s: base64: %v", path, err)
	}
	return blob
}

// verifySSHCertUnderCA proves that `certPath` was signed by the SSH CA whose private key is
// `caKeyPath`: the embedded `signature_key` equals the CA public key and the certificate signature
// verifies over the signed region.
func verifySSHCertUnderCA(t *testing.T, certPath, caKeyPath string) {
	t.Helper()

	// The CA's SSH public key, as OpenSSH itself serialises it: `ssh-keygen -y`.
	out := runCapture(t, "", nil, "ssh-keygen", "-y", "-f", caKeyPath)
	caBlob, err := base64.StdEncoding.DecodeString(strings.Fields(out)[1])
	if err != nil {
		t.Fatalf("decode ssh-keygen -y output: %v", err)
	}

	blob := sshCertB64Field(t, certPath)
	if !bytes.Contains(blob[:min(64, len(blob))], []byte("-cert-v01@openssh.com")) {
		t.Fatalf("blob does not carry the OpenSSH cert marker")
	}

	// Walk the fields; everything consumed up to the signature is the signed region.
	r := &sshReader{buf: blob}
	r.str()   // certtype
	r.str()   // nonce
	r.str()   // subject public key blob
	r.take(8) // serial
	r.take(4) // type
	r.str()   // key_id
	r.str()   // principals blob
	r.take(8) // valid_after
	r.take(8) // valid_before
	r.str()   // critical options blob
	r.str()   // extensions blob
	r.str()   // reserved
	sigKey := r.str()
	if r.err != nil {
		t.Fatalf("walk certificate: %v", r.err)
	}
	signed := blob[:len(blob)-len(r.buf)]
	if !bytes.Equal(sigKey, caBlob) {
		t.Fatalf("certificate signature key is not the declared CA key")
	}

	sigBlob := r.str() // the signature itself
	if r.err != nil {
		t.Fatalf("read signature: %v", r.err)
	}
	sr := &sshReader{buf: sigBlob}
	alg := string(sr.str())
	content := sr.str()
	if sr.err != nil {
		t.Fatalf("read signature fields: %v", sr.err)
	}

	switch alg {
	case "ecdsa-sha2-nistp256":
		// CA blob: string alg, string curve ident, string Q point.
		cr := &sshReader{buf: caBlob}
		if string(cr.str()) != "ecdsa-sha2-nistp256" {
			t.Fatal("CA key is not the algorithm the signature claims")
		}
		if string(cr.str()) != "nistp256" {
			t.Fatal("CA curve is not nistp256")
		}
		q := cr.str()
		if len(q) != 65 || q[0] != 4 {
			t.Fatalf("CA point is %d bytes, want a 65-byte uncompressed P-256 point", len(q))
		}
		pub, err := ecdsa.ParseUncompressedPublicKey(elliptic.P256(), q)
		if err != nil {
			t.Fatalf("CA public point invalid: %v", err)
		}
		digest := sha256.Sum256(signed)
		// `sshkey_ecdsa_sign` stores the signature as string(string(mpint r) || string(mpint s)).
		cr2 := &sshReader{buf: content}
		rb := cr2.str()
		sb := cr2.str()
		if cr2.err != nil || len(cr2.buf) != 0 {
			t.Fatalf("malformed ecdsa signature wrapper: %d bytes", len(content))
		}
		if !ecdsa.Verify(pub, digest[:], new(big.Int).SetBytes(rb), new(big.Int).SetBytes(sb)) {
			t.Fatal("ECDSA signature over the signed region does not verify")
		}
	case "ssh-ed25519":
		// CA blob: string alg, string key(32).
		cr := &sshReader{buf: caBlob}
		cr.str()
		key := cr.str()
		if len(key) != ed25519.PublicKeySize || len(content) != ed25519.SignatureSize {
			t.Fatal("short ed25519 key or signature")
		}
		if !ed25519.Verify(ed25519.PublicKey(key), signed, content) {
			t.Fatal("Ed25519 signature over the signed region does not verify")
		}
	default:
		t.Fatalf("unhandled signature algorithm %q", alg)
	}
}
