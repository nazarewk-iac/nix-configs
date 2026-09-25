// Package decl holds the certificate and CA declarations the CLI walks out of a flake.
//
// The declarations arrive as JSON from `nix eval --json`. A missing option is the empty set, never
// an error, so every read tolerates an absent key.
package decl

// Cert is one leaf certificate, from `kdn.certificates.certs.<name>`.
type Cert struct {
	Name              string   `json:"-"`
	CA                string   `json:"ca"`
	Type              string   `json:"type"`
	CommonName        string   `json:"commonName"`
	SANs              []string `json:"sans"`
	Principals        []string `json:"principals"`
	Directory         string   `json:"directory"`
	CertFile          string   `json:"certFile"`
	KeyFile           string   `json:"keyFile"`
	KeySource         string   `json:"keySource"`
	MinGenerationDate *string  `json:"minGenerationDate"`
}

// CA is one node of the CA graph, from `kdn.ca-dag.cas.<name>`.
type CA struct {
	Name              string  `json:"-"`
	Type              string  `json:"type"`
	Parent            *string `json:"parent"`
	CommonName        string  `json:"commonName"`
	Directory         string  `json:"directory"`
	CertFile          string  `json:"certFile"`
	KeyFile           string  `json:"keyFile"`
	KeySource         string  `json:"keySource"`
	Provisioner       *string `json:"provisioner"`
	SSH               bool    `json:"ssh"`
	MinGenerationDate *string `json:"minGenerationDate"`
}

// Certs is the `certs` attribute set of one target, keyed by certificate name.
type Certs map[string]Cert

// CAs is the `cas` attribute set of one target, keyed by CA name.
type CAs map[string]CA

// Target is one declaration site: a den host, a den home, a devenv shell or a legacy host.
type Target struct {
	// Name is a human-readable name, for example `denConfigurations.host-nixos`.
	Name string
	// Certs is the leaf set of this target. A missing option yields an empty set.
	Certs Certs
	// CAs is the CA graph of this target. A missing option yields an empty set.
	CAs CAs
}

// DedupKey is the identity of one certificate for deduplication. Two declarations with one key are
// one certificate. See design § 5.5.
func (c Cert) DedupKey() string {
	return c.CA + "\x00" + c.Type + "\x00" + c.CommonName + "\x00" + c.Directory + "\x00" + c.CertFile
}
