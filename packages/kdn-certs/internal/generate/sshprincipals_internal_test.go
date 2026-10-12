package generate

import (
	"reflect"
	"testing"

	"kdn-certs/internal/decl"
)

// TestSSHPrincipals checks the trailing-dot expansion a host certificate needs. A client that
// connects to a trailing-dot FQDN presents that exact name, and OpenSSH does not strip the dot
// before it matches a certificate principal. A user certificate and a short name are unchanged.
func TestSSHPrincipals(t *testing.T) {
	tests := []struct {
		name string
		cert decl.Cert
		want []string
	}{
		{
			name: "host certificate gains trailing-dot FQDNs",
			cert: decl.Cert{
				Type: "ssh-host",
				Principals: []string{
					"brys",
					"brys.lan.etra.net.int.kdn.im",
					"brys.netbird.cloud",
				},
			},
			want: []string{
				"brys",
				"brys.lan.etra.net.int.kdn.im",
				"brys.lan.etra.net.int.kdn.im.",
				"brys.netbird.cloud",
				"brys.netbird.cloud.",
			},
		},
		{
			name: "an already dotted principal is not doubled",
			cert: decl.Cert{
				Type:       "ssh-host",
				Principals: []string{"host.example.invalid."},
			},
			want: []string{"host.example.invalid."},
		},
		{
			name: "a duplicate stays once",
			cert: decl.Cert{
				Type:       "ssh-host",
				Principals: []string{"host.example.invalid", "host.example.invalid"},
			},
			want: []string{"host.example.invalid", "host.example.invalid."},
		},
		{
			name: "a user certificate passes through",
			cert: decl.Cert{
				Type:       "ssh-user",
				Principals: []string{"alice", "root"},
			},
			want: []string{"alice", "root"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := sshPrincipals(tt.cert); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("sshPrincipals() = %v, want %v", got, tt.want)
			}
		})
	}
}
