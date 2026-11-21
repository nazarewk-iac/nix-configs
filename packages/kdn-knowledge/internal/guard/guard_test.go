package guard

import (
	"strings"
	"testing"
)

func TestCheck(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		input    string
		allowed  []string
		wantErr  string
		wantFlag bool
		want     string
	}{
		{
			name:  "fleet endpoint",
			input: "https://llama-swap.brys.priv.nb.net.int.kdn.im/v1/",
			want:  "https://llama-swap.brys.priv.nb.net.int.kdn.im/v1",
		},
		{
			name:  "loopback name",
			input: "http://localhost:8080/v1",
			want:  "http://localhost:8080/v1",
		},
		{
			name:  "loopback address",
			input: "http://127.0.0.1:39700/v1",
			want:  "http://127.0.0.1:39700/v1",
		},
		{
			name:  "loopback ipv6",
			input: "http://[::1]:8080/v1",
			want:  "http://[::1]:8080/v1",
		},
		{
			name:     "openai is refused",
			input:    "https://api.openai.com/v1",
			wantErr:  `endpoint host "api.openai.com" is not allowed`,
			wantFlag: true,
		},
		{
			name:     "look-alike suffix is refused",
			input:    "https://brys.priv.nb.net.int.kdn.im.evil.example/v1",
			wantErr:  `endpoint host "brys.priv.nb.net.int.kdn.im.evil.example" is not allowed`,
			wantFlag: true,
		},
		{
			name:     "nested look-alike is refused",
			input:    "https://evil.nb.net.int.kdn.im.attacker.test/v1",
			wantErr:  `endpoint host "evil.nb.net.int.kdn.im.attacker.test" is not allowed`,
			wantFlag: true,
		},
		{
			name:     "userinfo cannot smuggle a host",
			input:    "https://llama-swap.brys.priv.nb.net.int.kdn.im@api.openai.com/v1",
			wantErr:  `endpoint host "api.openai.com" is not allowed`,
			wantFlag: true,
		},
		{
			name:     "plain http is allowed only on the allow-list",
			input:    "http://example.test/v1",
			wantErr:  `endpoint host "example.test" is not allowed`,
			wantFlag: true,
		},
		{
			name:    "other scheme is refused",
			input:   "ftp://localhost/v1",
			wantErr: `uses scheme "ftp"`,
		},
		{
			name:    "empty input",
			input:   "  ",
			wantErr: "endpoint is empty",
		},
		{
			name:    "no host",
			input:   "https:///v1",
			wantErr: "has no host",
		},
		{
			name:    "explicit allow-host extends the list",
			input:   "https://api.openai.com/v1",
			allowed: []string{"API.OpenAI.com"},
			want:    "https://api.openai.com/v1",
		},
		{
			name:     "allow-host does not match a suffix",
			input:    "https://api.openai.com/v1",
			allowed:  []string{"openai.com"},
			wantErr:  `endpoint host "api.openai.com" is not allowed`,
			wantFlag: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			got, err := Check(test.input, test.allowed)
			if test.wantErr != "" {
				if err == nil {
					t.Fatalf("Check(%q) = %q, want error", test.input, got)
				}
				if !strings.Contains(err.Error(), test.wantErr) {
					t.Fatalf("Check(%q) error = %q, want it to contain %q", test.input, err, test.wantErr)
				}
				if test.wantFlag && !strings.Contains(err.Error(), "--allow-host") {
					t.Fatalf("Check(%q) error = %q, want it to name --allow-host", test.input, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("Check(%q) unexpected error: %v", test.input, err)
			}
			if got != test.want {
				t.Fatalf("Check(%q) = %q, want %q", test.input, got, test.want)
			}
		})
	}
}
