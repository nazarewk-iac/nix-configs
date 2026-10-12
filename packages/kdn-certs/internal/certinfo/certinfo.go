// Package certinfo reads the two fields the rotation test needs from an existing certificate.
//
// The rotation test compares a certificate's own `notBefore` against the declared
// `minGenerationDate`, and its issuer common name against the declared CA common name. Both values
// come from the committed public certificate, so the read is pure Go and needs no `step` call and
// no network. See design § 5.7.
//
// Two certificate encodings reach the tree. A TLS leaf is a PEM X.509 certificate. An SSH leaf is an
// OpenSSH certificate — one line, `<type> <base64-blob> [comment]` — written by `ssh-keygen -s`. The
// OpenSSH certificate has no issuer common name, so `Read` reports `IsSSH` and the caller skips the
// issuer test for it. See sub-task 008.
package certinfo

import (
	"bytes"
	"crypto/x509"
	"encoding/base64"
	"encoding/binary"
	"encoding/pem"
	"fmt"
	"os"
	"strings"
	"time"
)

// Info is the state of a certificate that is already on disk.
type Info struct {
	// NotBefore is the certificate's own not-before date. For an SSH certificate it is the
	// certificate `valid_after` field.
	NotBefore time.Time
	// NotAfter is the certificate's expiry. The zero time means "no expiry recorded", which an
	// OpenSSH "indefinite" `valid_before` maps to.
	NotAfter time.Time
	// IssuerCN is the common name of the certificate issuer. It is empty for an SSH certificate,
	// which carries no issuer common name.
	IssuerCN string
	// IsSSH marks an OpenSSH certificate. The rotation test reads it to skip the issuer comparison,
	// which only an X.509 issuer supports.
	IsSSH bool
}

// Read parses one committed certificate, X.509 PEM or OpenSSH, and returns its not-before date and
// issuer common name.
//
// A missing file is not an error: the caller treats it as "no certificate yet". A file that holds
// neither a PEM block nor a recognizable OpenSSH certificate line is an error, so a corrupt file
// fails loudly instead of silently regenerating.
func Read(path string) (*Info, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read certificate %s: %w", path, err)
	}

	if isSshCertificate(raw) {
		return readSSH(path, raw)
	}

	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("certificate %s holds no PEM block", path)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse certificate %s: %w", path, err)
	}

	return &Info{
		NotBefore: cert.NotBefore.UTC(),
		NotAfter:  cert.NotAfter.UTC(),
		IssuerCN:  cert.Issuer.CommonName,
	}, nil
}

// isSshCertificate reports whether the file is an OpenSSH certificate line, for example
// `ssh-ed25519-cert-v01@openssh.com AAAA...`. The marker `-cert-v01@openssh.com` only ever appears in
// an OpenSSH certificate key type.
func isSshCertificate(raw []byte) bool {
	head := raw
	if len(head) > 64 {
		head = head[:64]
	}
	return bytes.HasPrefix(head, []byte("ssh-")) && bytes.Contains(raw, []byte("-cert-v01@openssh.com"))
}

// readSSH parses the OpenSSH certificate wire format enough to recover `valid_after` and the
// certificate type.
//
// The blob is the base64 field of the first line. The wire layout, in order, is: string certtype
// (`ssh-…-cert-v01@openssh.com`), string nonce, string key, uint64 serial, uint32 cert_type
// (1 = user, 2 = host), string key_id, string principals (a nested blob, skipped here), then uint64
// valid_after and uint64 valid_before. Only cert_type and the two validity bounds are needed; the
// rest is read to advance the cursor. The layout is `sshkey_cert_serialize` in portable OpenSSH
// `sshkey.c`.
func readSSH(path string, raw []byte) (*Info, error) {
	fields := strings.Fields(string(raw))
	if len(fields) < 2 {
		return nil, fmt.Errorf("certificate %s is not an OpenSSH certificate line", path)
	}
	blob, err := decodeBase64(fields[1])
	if err != nil {
		return nil, fmt.Errorf("decode OpenSSH certificate %s: %w", path, err)
	}

	r := &byteReader{buf: blob}
	if _, err := r.str(); err != nil { // certtype
		return nil, sshFieldErr(path, "certtype", err)
	}
	if _, err := r.str(); err != nil { // nonce
		return nil, sshFieldErr(path, "nonce", err)
	}
	if _, err := r.str(); err != nil { // subject public key blob
		return nil, sshFieldErr(path, "key", err)
	}
	if _, err := r.u64(); err != nil { // serial
		return nil, sshFieldErr(path, "serial", err)
	}
	certType, err := r.u32()
	if err != nil {
		return nil, sshFieldErr(path, "cert_type", err)
	}
	if certType != 1 && certType != 2 {
		return nil, fmt.Errorf("certificate %s has unknown OpenSSH cert type %d", path, certType)
	}
	if _, err := r.str(); err != nil { // key id
		return nil, sshFieldErr(path, "key_id", err)
	}
	if _, err := r.str(); err != nil { // principals blob (nested list, skipped)
		return nil, sshFieldErr(path, "principals", err)
	}

	validAfter, err := r.u64()
	if err != nil {
		return nil, sshFieldErr(path, "valid_after", err)
	}
	validBefore, err := r.u64()
	if err != nil {
		return nil, sshFieldErr(path, "valid_before", err)
	}

	return &Info{
		NotBefore: time.Unix(int64(validAfter), 0).UTC(),
		NotAfter:  sshNotAfter(validBefore),
		IsSSH:     true,
	}, nil
}

// sshNotAfter converts an OpenSSH `valid_before` epoch. `ssh-keygen -V ...:none` and very large
// sentinels encode "indefinite"; anything beyond the year 9999 maps to the zero time, which the
// caller reads as "never expires".
func sshNotAfter(validBefore uint64) time.Time {
	const maxEpoch = 253402300799 // year 9999
	if validBefore > maxEpoch {
		return time.Time{}
	}
	return time.Unix(int64(validBefore), 0).UTC()
}

func sshFieldErr(path, field string, err error) error {
	return fmt.Errorf("parse OpenSSH certificate %s at %s: %w", path, field, err)
}

// decodeBase64 accepts the base64 field of an OpenSSH certificate line, with or without `=` padding.
// `ssh-keygen` writes unpadded standard-alphabet base64; a copied file may carry padding.
func decodeBase64(s string) ([]byte, error) {
	if b, err := base64.StdEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	return base64.RawStdEncoding.DecodeString(s)
}

// byteReader reads SSH wire scalars from a byte slice. A string is a uint32 length then that many
// bytes. Reads past the end return an error, so a truncated blob never yields a wrong value.
type byteReader struct {
	buf []byte
	pos int
}

func (r *byteReader) u32() (uint32, error) {
	if r.pos+4 > len(r.buf) {
		return 0, fmt.Errorf("short read")
	}
	v := binary.BigEndian.Uint32(r.buf[r.pos:])
	r.pos += 4
	return v, nil
}

func (r *byteReader) u64() (uint64, error) {
	if r.pos+8 > len(r.buf) {
		return 0, fmt.Errorf("short read")
	}
	v := binary.BigEndian.Uint64(r.buf[r.pos:])
	r.pos += 8
	return v, nil
}

func (r *byteReader) str() ([]byte, error) {
	n, err := r.u32()
	if err != nil {
		return nil, err
	}
	if r.pos+int(n) > len(r.buf) {
		return nil, fmt.Errorf("short read")
	}
	v := r.buf[r.pos : r.pos+int(n)]
	r.pos += int(n)
	return v, nil
}
