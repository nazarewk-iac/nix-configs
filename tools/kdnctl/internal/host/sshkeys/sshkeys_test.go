package sshkeys

import (
	"os"
	osexec "os/exec"
	"testing"
)

func TestEqualKey(t *testing.T) {
	const body = "AAAAC3NzaC1lZDI1NTE5AAAAIGadQ+IKTQ5Bkm2ngx0ZmvPn"
	tests := []struct {
		name   string
		a, b   string
		public bool
		want   bool
	}{
		{
			name:   "private keys compare byte for byte",
			a:      "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n",
			b:      "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n",
			public: false,
			want:   true,
		},
		{
			name:   "private keys differ",
			a:      "abc",
			b:      "abd",
			public: false,
			want:   false,
		},
		{
			name:   "public keys ignore the comment",
			a:      "ssh-ed25519 " + body + " root@briv\n",
			b:      "ssh-ed25519 " + body,
			public: true,
			want:   true,
		},
		{
			name:   "public keys with a different body differ",
			a:      "ssh-ed25519 " + body + " root@briv",
			b:      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINROMWwh26aKZthWiFGlZG9Y",
			public: true,
			want:   false,
		},
		{
			name:   "a public key needs a body",
			a:      "ssh-ed25519",
			b:      "ssh-ed25519 " + body,
			public: true,
			want:   false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := equalKey([]byte(tt.a), []byte(tt.b), tt.public); got != tt.want {
				t.Errorf("equalKey() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDerivePublicKey(t *testing.T) {
	private, err := deriveTestKey(t)
	if err != nil {
		t.Fatal(err)
	}
	public, err := derivePublicKey(private)
	if err != nil {
		t.Fatalf("derivePublicKey: %v", err)
	}
	if len(public) == 0 {
		t.Fatal("derivePublicKey returned nothing")
	}
	if !equalKey(public, public, true) {
		t.Fatal("derived public key does not compare equal to itself")
	}
	if equalKey(public, private, true) {
		t.Fatal("the private key was accepted as a public key")
	}
}

// deriveTestKey generates one throwaway ed25519 key with `ssh-keygen`.
func deriveTestKey(t *testing.T) ([]byte, error) {
	t.Helper()
	dir := t.TempDir()
	path := dir + "/key"
	if out, err := osexec.Command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", path).CombinedOutput(); err != nil {
		t.Skipf("ssh-keygen unavailable: %v: %s", err, out)
	}
	return os.ReadFile(path)
}
