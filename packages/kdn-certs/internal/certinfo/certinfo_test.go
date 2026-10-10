package certinfo

import (
	"os"
	"path/filepath"
	"testing"
)

// The fixtures are real OpenSSH certificates written by `ssh-keygen -s` with a fixed validity window
// requested as `-V 20300101000000:20310101000000`. `ssh-keygen` reads that wall-clock in its local
// timezone (CET, UTC+1), so the stored `valid_after` is the epoch 1893452400 (2029-12-31T23:00:00Z)
// and `valid_before` is 1924988400. The value is frozen in the fixture, so the assertion holds on any
// machine at any time. The user fixture is unpadded base64; the host fixture carries `=` padding, so
// both encodings are exercised.
const sshUserCert = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIN683W7viDUnlofFUwDT15dC6jNA0ZvkymkvfxrdGhaVAAAAIK691/7hoNUUXUpfRr7LkA9bBqVDCy/8ch+kU0M+xMAKAAAAAAAAAAAAAAABAAAAFWFsaWNlQGV4YW1wbGUuaW52YWxpZAAAAAkAAAAFYWxpY2UAAAAAcNvKcAAAAAByvP3wAAAAAAAAAIIAAAAVcGVybWl0LVgxMS1mb3J3YXJkaW5nAAAAAAAAABdwZXJtaXQtYWdlbnQtZm9yd2FyZGluZwAAAAAAAAAWcGVybWl0LXBvcnQtZm9yd2FyZGluZwAAAAAAAAAKcGVybWl0LXB0eQAAAAAAAAAOcGVybWl0LXVzZXItcmMAAAAAAAAAAAAAAGgAAAATZWNkc2Etc2hhMi1uaXN0cDI1NgAAAAhuaXN0cDI1NgAAAEEEmsCVpNNEohXVFkWFGZchFybWPPFJIWfM9NysIPns/bHYR3hAEWlRHBODjy3hljBqtf1x5v2fiz6q2vlZrMvhpgAAAGQAAAATZWNkc2Etc2hhMi1uaXN0cDI1NgAAAEkAAAAgIDZogJ/th1Ug2ClWF7v2ezjQyeva8DNzW4GtrXCuDb4AAAAhAOJDsV/5BWTcd9uObOP04Pt5KPpjBA94k7Kcw8E9rcYF kdn@oams\n"

const sshHostCert = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIGRFAUdlEi7tmACcDAqg2W/tzqIIol395D/kqMsArPj7AAAAIFIN8okv/nR7AARbBbFf9cjU0f9rpZrU2wMS2qjEIOLYAAAAAAAAAAAAAAACAAAABHRlc3QAAAAQAAAADGhvc3QuZXhhbXBsZQAAAABw28pwAAAAAHK8/fAAAAAAAAAAAAAAAAAAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJrAlaTTRKIV1RZFhRmXIRcm1jzxSSFnzPTcrCD57P2x2Ed4QBFpURwTg48t4ZYwarX9ceb9n4s+qtr5WazL4aYAAABkAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAABJAAAAIQDBzqXF01qv3uvgrwNYW0o8lUuIXOEvfmYavBEwXBSP9AAAACA1o2TlGr+wwo3T/Mb8CTuxGGAk5ppzQKK4mA6lDOL4vw== kdn@oams\n"

// wantValidAfter is the stored `valid_after` of both fixtures (2029-12-31T23:00:00Z).
const wantValidAfter = 1893452400

func writeFixture(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestReadSSHUserCertificate(t *testing.T) {
	info, err := Read(writeFixture(t, "id_ed25519-cert.pub", sshUserCert))
	if err != nil {
		t.Fatalf("Read user cert: %v", err)
	}
	if info == nil {
		t.Fatal("Read returned nil for a present file")
	}
	if !info.IsSSH {
		t.Errorf("IsSSH = false, want true")
	}
	if got := info.NotBefore.Unix(); got != wantValidAfter {
		t.Errorf("NotBefore epoch = %d, want %d", got, wantValidAfter)
	}
	// An OpenSSH certificate has no issuer common name.
	if info.IssuerCN != "" {
		t.Errorf("IssuerCN = %q, want empty for an SSH certificate", info.IssuerCN)
	}
}

func TestReadSSHHostCertificatePadded(t *testing.T) {
	info, err := Read(writeFixture(t, "id_host-cert.pub", sshHostCert))
	if err != nil {
		t.Fatalf("Read host cert (padded base64): %v", err)
	}
	if !info.IsSSH {
		t.Errorf("IsSSH = false, want true")
	}
	if got := info.NotBefore.Unix(); got != wantValidAfter {
		t.Errorf("NotBefore epoch = %d, want %d", got, wantValidAfter)
	}
}

// TestReadMissingFileStaysNil documents that the "no certificate yet" signal is unchanged: a missing
// file is nil, nil. The SSH branch must not turn a missing file into a parse error.
func TestReadMissingFileStaysNil(t *testing.T) {
	info, err := Read(filepath.Join(t.TempDir(), "absent.pub"))
	if err != nil {
		t.Fatalf("Read missing file: %v", err)
	}
	if info != nil {
		t.Errorf("Read missing file returned %+v, want nil", info)
	}
}

// TestReadTruncatedSSHCertificateFails proves a corrupt SSH certificate fails loudly instead of
// returning a wrong date. The blob is cut short before `valid_after`.
func TestReadTruncatedSSHCertificateFails(t *testing.T) {
	// Keep the type prefix and marker, truncate the base64 field to a few bytes.
	truncated := "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1\n"
	if _, err := Read(writeFixture(t, "bad-cert.pub", truncated)); err == nil {
		t.Fatal("Read truncated SSH certificate returned nil error, want a parse error")
	}
}
