// Package guard enforces the "local models only" rule of the knowledge pipeline.
//
// The endpoint must pass Check before the first request. The allow-list is deliberately narrow:
// loopback, the NetBird domain of the fleet, and hosts named with --allow-host.
package guard

import (
	"fmt"
	"net/url"
	"strings"
)

// FleetSuffix is the NetBird domain that the local fleet lives under.
const FleetSuffix = ".nb.net.int.kdn.im"

// loopback holds the hosts that always pass.
var loopback = map[string]bool{
	"localhost": true,
	"127.0.0.1": true,
	"::1":       true,
}

// Check validates a model endpoint and returns it without a trailing slash.
//
// The error names the offending host and the flag that would allow it, so an operator can fix
// the call without reading the source.
func Check(endpoint string, allowHosts []string) (string, error) {
	raw := strings.TrimSpace(endpoint)
	if raw == "" {
		return "", fmt.Errorf("endpoint is empty; pass --endpoint or set KDN_KNOWLEDGE_ENDPOINT")
	}
	parsed, err := url.Parse(raw)
	if err != nil {
		return "", fmt.Errorf("endpoint %q is not a URL: %w", raw, err)
	}
	switch parsed.Scheme {
	case "http", "https":
	default:
		return "", fmt.Errorf("endpoint %q uses scheme %q; only http and https are allowed", raw, parsed.Scheme)
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "" {
		return "", fmt.Errorf("endpoint %q has no host", raw)
	}
	if Allowed(host, allowHosts) {
		return strings.TrimRight(raw, "/"), nil
	}
	return "", fmt.Errorf(
		"endpoint host %q is not allowed: this pipeline runs on local models only. "+
			"The fleet lives under %s; pass --allow-host %s to permit another host on purpose",
		host, strings.TrimPrefix(FleetSuffix, "."), host)
}

// Allowed reports whether host passes the allow-list. The check is exact for loopback and for
// --allow-host entries, and a dot-boundary suffix match for the fleet domain.
func Allowed(host string, allowHosts []string) bool {
	host = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(host), "."))
	if loopback[host] {
		return true
	}
	if strings.HasSuffix(host, FleetSuffix) && len(host) > len(FleetSuffix) {
		return true
	}
	for _, allowed := range allowHosts {
		name := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(allowed), "."))
		if name == "" {
			continue
		}
		if name == host {
			return true
		}
	}
	return false
}

// HostOf returns the lowercased host of an endpoint, or "" when it cannot be parsed.
func HostOf(endpoint string) string {
	parsed, err := url.Parse(strings.TrimSpace(endpoint))
	if err != nil {
		return ""
	}
	return strings.ToLower(parsed.Hostname())
}
