// kdn-ssh-access: host-connectivity-graph ssh access dispatcher.
//
// Each host declares how it is reached from other places (`reachedFrom` edges): from the
// "internet" (an entry point, address from a WAN uplink file or a public literal), from "lan"
// (direct, only when on that LAN), or from another host (a relay hop, where the address is the
// target as that relay sees it — e.g. a NetBird name resolved on the relay).
//
// To connect to a host the dispatcher pathfinds `me -> target`, ranks paths by summed edge
// priority (hop-count tiebreak), and for the best reachable path either dials directly (1 edge)
// or builds an `ssh` ProxyJump chain (>=2 edges). Only the first (local) hop is probed; the rest
// are resolved on-the-hop by ssh. No local overlay (NetBird) is needed.
//
// Modes: proxy <host> <port> | ssh [args...] | emit-ssh-config | route <host> | debug [host...].
// The host arg is `kdn-<name>[+tag]...`; tags: direct, remote, via=<host>, 4, 6.
//
// `debug` is the entry point when a connection fails: it validates the graph, resolves the uplink
// and edge addresses, checks the ssh binary and the agent, reports the reachability cache, probes
// the first hop, and names the route a real run selects. See README.md.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/BurntSushi/toml"
	"sigs.k8s.io/yaml"
)

// ---------- configuration ----------

type Config struct {
	Defaults              Defaults          `json:"defaults"`
	IdentityAgentPatterns []string          `json:"identityAgentPatterns"`
	Uplinks               map[string]Uplink `json:"uplinks"`
	Hosts                 map[string]Host   `json:"hosts"`
}

type Defaults struct {
	User                string `json:"user"`
	IdentityFile        string `json:"identityFile"`
	LanProbeTimeoutMs   int    `json:"lanProbeTimeoutMs"`
	CacheTtlSeconds     int    `json:"cacheTtlSeconds"`
	IPVersionPreference string `json:"ipVersionPreference"` // ipv6-first | ipv4-first
	MaxHops             int    `json:"maxHops"`
}

type Uplink struct {
	IPv4     string `json:"ipv4"`
	IPv6     string `json:"ipv6"`
	IPv4File string `json:"ipv4File"`
	IPv6File string `json:"ipv6File"`
}

type Edge struct {
	From        string `json:"from"` // "internet" | "lan" | "<host>"
	Uplink      string `json:"uplink"`
	Address     string `json:"address"`
	AddressFile string `json:"addressFile"`
	Port        int    `json:"port"`
	Priority    int    `json:"priority"`
}

type Host struct {
	User         string `json:"user"`
	HostKeyAlias string `json:"hostKeyAlias"`
	ReachedFrom  []Edge `json:"reachedFrom"`
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	switch strings.ToLower(filepath.Ext(path)) {
	case ".toml":
		var m map[string]any
		if err := toml.Unmarshal(data, &m); err != nil {
			return nil, fmt.Errorf("parse toml %s: %w", path, err)
		}
		j, err := json.Marshal(m)
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(j, &cfg); err != nil {
			return nil, err
		}
	case ".yaml", ".yml":
		if err := yaml.Unmarshal(data, &cfg); err != nil {
			return nil, fmt.Errorf("parse yaml %s: %w", path, err)
		}
	default:
		if json.Unmarshal(data, &cfg) != nil {
			if err := yaml.Unmarshal(data, &cfg); err != nil {
				return nil, fmt.Errorf("parse config %s (json/yaml): %w", path, err)
			}
		}
	}
	if cfg.Defaults.LanProbeTimeoutMs == 0 {
		cfg.Defaults.LanProbeTimeoutMs = 1000
	}
	if cfg.Defaults.CacheTtlSeconds == 0 {
		cfg.Defaults.CacheTtlSeconds = 30
	}
	if cfg.Defaults.IPVersionPreference == "" {
		cfg.Defaults.IPVersionPreference = "ipv6-first"
	}
	if cfg.Defaults.MaxHops == 0 {
		cfg.Defaults.MaxHops = 6
	}
	return &cfg, nil
}

// ---------- helpers ----------

var debug = os.Getenv("KDN_SSH_ACCESS_DEBUG") != ""

func dbg(format string, a ...any) {
	if debug {
		fmt.Fprintf(os.Stderr, "kdn-ssh-access: "+format+"\n", a...)
	}
}

func fatal(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "kdn-ssh-access: "+format+"\n", a...)
	os.Exit(1)
}

func readFileValue(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	s := strings.TrimSpace(string(data))
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = strings.TrimSpace(s[:i])
	}
	if s == "" {
		return "", fmt.Errorf("file %s is empty", path)
	}
	return s, nil
}

func cacheDir() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return filepath.Join(d, "kdn-ssh-access")
	}
	return filepath.Join(os.TempDir(), "kdn-ssh-access") // macOS: $TMPDIR = DARWIN_USER_TEMP_DIR
}

func sanitize(s string) string {
	return strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			return r
		}
		return '_'
	}, s)
}

var (
	fpOnce sync.Once
	fpVal  string
)

// netFingerprint returns a short id of the current network: the local source address that the
// routing table selects for a default-route destination. A UDP "connect" sends no packets; it
// only binds the socket. The value changes when the network changes (VPN up/down, other WiFi), so
// a stale reachability verdict from the previous network does not carry over. The value is memoized
// per process (each ProxyCommand is a fresh process).
func netFingerprint() string {
	fpOnce.Do(func() {
		c, err := net.Dial("udp", "192.0.2.1:9") // TEST-NET-1: no packets leave the host
		if err != nil {
			fpVal = "nonet"
			return
		}
		defer c.Close()
		if ua, ok := c.LocalAddr().(*net.UDPAddr); ok {
			fpVal = sanitize(ua.IP.String())
			return
		}
		fpVal = "nonet"
	})
	return fpVal
}

// Reachability verdicts are cached (flock-guard, TTL) under the runtime dir so the many
// ProxyCommand invocations of one ssh/scp/git burst share the result. The cache key includes the
// network fingerprint, so a network change does not reuse a stale verdict. Only local (first-hop)
// addresses get a probe; remote relay edges are declared, not probed.
func verdictFile(addr string) string {
	dir := filepath.Join(cacheDir(), "reach")
	_ = os.MkdirAll(dir, 0o700)
	return filepath.Join(dir, netFingerprint()+"_"+sanitize(addr))
}

func cachedVerdict(cfg *Config, addr string) (ok bool, known bool) {
	f, err := os.Open(verdictFile(addr))
	if err != nil {
		return false, false
	}
	defer f.Close()
	syscall.Flock(int(f.Fd()), syscall.LOCK_SH)
	fi, _ := f.Stat()
	buf := make([]byte, 1)
	n, _ := f.Read(buf)
	syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	ttl := time.Duration(cfg.Defaults.CacheTtlSeconds) * time.Second
	if fi != nil && time.Since(fi.ModTime()) < ttl && n == 1 {
		return buf[0] == '1', true
	}
	return false, false
}

func storeVerdict(addr string, ok bool) {
	// Open without O_TRUNC, then truncate under the exclusive lock so a concurrent reader never
	// sees a half-truncated file.
	f, err := os.OpenFile(verdictFile(addr), os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	syscall.Flock(int(f.Fd()), syscall.LOCK_EX)
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	f.Truncate(0)
	f.Seek(0, 0)
	if ok {
		f.Write([]byte("1"))
	} else {
		f.Write([]byte("0"))
	}
}

// readVerdict returns the raw cached value and its age, with no TTL check. The debug mode uses it
// to show a stale verdict that a normal run would still honour.
func readVerdict(addr string) (val bool, age time.Duration, known bool) {
	fi, err := os.Stat(verdictFile(addr))
	if err != nil {
		return false, 0, false
	}
	data, err := os.ReadFile(verdictFile(addr))
	if err != nil || len(data) < 1 {
		return false, 0, false
	}
	return data[0] == '1', time.Since(fi.ModTime()), true
}

// clearVerdicts deletes every cached verdict for the current network. It returns the count removed.
func clearVerdicts() int {
	dir := filepath.Join(cacheDir(), "reach")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	n := 0
	prefix := netFingerprint() + "_"
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), prefix) {
			continue
		}
		if os.Remove(filepath.Join(dir, e.Name())) == nil {
			n++
		}
	}
	return n
}

// countVerdicts returns the number of cached verdicts for the current network and for all others.
func countVerdicts() (mine, others int) {
	entries, err := os.ReadDir(filepath.Join(cacheDir(), "reach"))
	if err != nil {
		return 0, 0
	}
	prefix := netFingerprint() + "_"
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), prefix) {
			mine++
		} else {
			others++
		}
	}
	return mine, others
}

// probeFresh dials host:port and ignores the cache, so the debug report states the current truth.
// It does not store the verdict — a debug run must not change what the next real run sees.
func probeFresh(host string, port int, timeout time.Duration) (time.Duration, error) {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), timeout)
	took := time.Since(start)
	if err == nil {
		conn.Close()
	}
	return took, err
}

// dialCached returns a live connection to host:port (the one that the direct pipe then uses — no
// throwaway probe). It returns nil at once when a fresh negative verdict is cached, and it records
// the new verdict either way.
func dialCached(cfg *Config, host string, port int) net.Conn {
	addr := net.JoinHostPort(host, strconv.Itoa(port))
	if ok, known := cachedVerdict(cfg, addr); known && !ok {
		dbg("cache %s -> unreachable (skip)", addr)
		return nil
	}
	conn, err := net.DialTimeout("tcp", addr, time.Duration(cfg.Defaults.LanProbeTimeoutMs)*time.Millisecond)
	storeVerdict(addr, err == nil)
	if err != nil {
		dbg("dial %s -> %v", addr, err)
		return nil
	}
	dbg("dial %s -> ok", addr)
	return conn
}

// reachable probes host:port for the jump-entrypoint case (the ssh child then makes the real
// connection). It consults and updates the shared cache.
func reachable(cfg *Config, host string, port int) bool {
	addr := net.JoinHostPort(host, strconv.Itoa(port))
	if ok, known := cachedVerdict(cfg, addr); known {
		dbg("cache %s -> %v", addr, ok)
		return ok
	}
	conn, err := net.DialTimeout("tcp", addr, time.Duration(cfg.Defaults.LanProbeTimeoutMs)*time.Millisecond)
	ok := err == nil
	if ok {
		conn.Close()
	}
	storeVerdict(addr, ok)
	dbg("probe %s -> %v", addr, ok)
	return ok
}

// familyOK reports whether addr matches the requested family ("4"/"6"; "" = any). It filters only
// IP literals. A hostname (not a parseable IP) always passes, because the family is unknown until
// name resolution on the hop that dials it.
func familyOK(addr, family string) bool {
	if family != "4" && family != "6" {
		return true
	}
	ip := net.ParseIP(addr)
	if ip == nil {
		return true // hostname: family is not statically known
	}
	isV6 := ip.To4() == nil
	if family == "6" {
		return isV6
	}
	return !isV6
}

// entryAddrs returns the ordered candidate local addresses for an origin edge (internet/lan). It
// resolves uplink file refs and applies the IPv6/IPv4 preference plus an optional family override.

func entryAddrs(cfg *Config, e Edge, family string) ([]string, error) {
	// Literal / file address: a single value, still subject to the family filter.
	lit := e.Address
	if lit == "" && e.AddressFile != "" {
		v, err := readFileValue(e.AddressFile)
		if err != nil {
			return nil, err
		}
		lit = v
	}
	if lit != "" {
		if !familyOK(lit, family) {
			return nil, fmt.Errorf("address %q does not match requested family %q", lit, family)
		}
		return []string{lit}, nil
	}
	if e.Uplink == "" {
		return nil, fmt.Errorf("origin edge has no address/addressFile/uplink")
	}
	u, ok := cfg.Uplinks[e.Uplink]
	if !ok {
		return nil, fmt.Errorf("unknown uplink %q", e.Uplink)
	}
	resolve := func(lit, file string) string {
		if lit != "" {
			return lit
		}
		if file != "" {
			if v, err := readFileValue(file); err == nil {
				return v
			} else {
				dbg("uplink file %s: %v", file, err)
			}
		}
		return ""
	}
	v4 := resolve(u.IPv4, u.IPv4File)
	v6 := resolve(u.IPv6, u.IPv6File)
	order := []string{v6, v4}
	if cfg.Defaults.IPVersionPreference == "ipv4-first" {
		order = []string{v4, v6}
	}
	var out []string
	for _, a := range order {
		if a != "" && familyOK(a, family) {
			out = append(out, a)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("uplink %q has no address for the requested family", e.Uplink)
	}
	return out, nil
}

// edgeLiteral resolves a relay/target hop address (a literal, optionally read from a local file).
func edgeLiteral(e Edge) (string, error) {
	if e.Address != "" {
		return e.Address, nil
	}
	if e.AddressFile != "" {
		return readFileValue(e.AddressFile)
	}
	return "", fmt.Errorf("edge (from %q) has no address/addressFile", e.From)
}

// ---------- graph pathfinding ----------

type step struct {
	edge Edge
	dest string // host reached by this edge
}

func edgeFromMatches(e Edge, cur string) bool {
	if cur == "me" {
		return e.From == "internet" || e.From == "lan"
	}
	return e.From == cur
}

func findPaths(cfg *Config, target string) [][]step {
	var out [][]step
	var dfs func(cur string, visited map[string]bool, path []step)
	dfs = func(cur string, visited map[string]bool, path []step) {
		if cur == target && len(path) > 0 {
			cp := make([]step, len(path))
			copy(cp, path)
			out = append(out, cp)
			return
		}
		if len(path) >= cfg.Defaults.MaxHops {
			return
		}
		for hname, h := range cfg.Hosts {
			if visited[hname] {
				continue
			}
			for _, e := range h.ReachedFrom {
				if !edgeFromMatches(e, cur) {
					continue
				}
				visited[hname] = true
				dfs(hname, visited, append(path, step{edge: e, dest: hname}))
				visited[hname] = false
			}
		}
	}
	dfs("me", map[string]bool{}, nil)
	return out
}

func pathPriority(p []step) int {
	sum := 0
	for _, s := range p {
		sum += s.edge.Priority
	}
	return sum
}

func rankPaths(paths [][]step) {
	sort.SliceStable(paths, func(i, j int) bool {
		pi, pj := pathPriority(paths[i]), pathPriority(paths[j])
		if pi != pj {
			return pi < pj
		}
		return len(paths[i]) < len(paths[j])
	})
}

// ---------- spec / tags ----------

type spec struct {
	host       string
	onlyDirect bool
	onlyRemote bool
	via        string
	family     string
}

func parseSpec(sshHost string) spec {
	name := strings.TrimPrefix(sshHost, "kdn-")
	parts := strings.Split(name, "+")
	s := spec{host: parts[0]}
	for _, t := range parts[1:] {
		switch {
		case t == "direct":
			s.onlyDirect = true
		case t == "remote":
			s.onlyRemote = true
		case t == "4" || t == "6":
			s.family = t
		case strings.HasPrefix(t, "via="):
			s.via = strings.TrimPrefix(t, "via=")
		default:
			dbg("ignoring unknown tag %q", t)
		}
	}
	return s
}

// filterReason returns "" when the spec's tags keep this path, or the reason that drops it. The
// debug mode prints the reason; filterPaths only needs the empty/non-empty result.
func filterReason(p []step, s spec) string {
	// +direct keeps LAN-origin paths; +remote keeps internet-origin paths (the WAN entry or a
	// relay chain). The first edge's origin is always "lan" or "internet".
	if s.onlyDirect && !(len(p) >= 1 && p[0].edge.From == "lan") {
		return "+direct needs a lan-origin path"
	}
	if s.onlyRemote && !(len(p) >= 1 && p[0].edge.From == "internet") {
		return "+remote needs an internet-origin path"
	}
	if s.via != "" {
		for _, st := range p {
			if st.dest == s.via {
				return ""
			}
		}
		return fmt.Sprintf("+via=%s is not on this path", s.via)
	}
	return ""
}

func filterPaths(paths [][]step, s spec) [][]step {
	var out [][]step
	for _, p := range paths {
		if filterReason(p, s) == "" {
			out = append(out, p)
		}
	}
	return out
}

func pathString(p []step) string {
	parts := []string{"me"}
	for _, s := range p {
		parts = append(parts, fmt.Sprintf("%s(%s)", s.dest, s.edge.From))
	}
	return strings.Join(parts, " -> ")
}

// ---------- connect ----------

func hostUser(cfg *Config, name string) string {
	if h, ok := cfg.Hosts[name]; ok && h.User != "" {
		return h.User
	}
	return cfg.Defaults.User
}

// tryPath attempts one ranked path. Returns true if it connected (proxied), false to try the next.
func tryPath(cfg *Config, self string, p []step, s spec) bool {
	origin := p[0].edge // from internet/lan
	addrs, err := entryAddrs(cfg, origin, s.family)
	if err != nil {
		dbg("path %s: %v", pathString(p), err)
		return false
	}
	for _, addr := range addrs {
		if len(p) == 1 {
			// direct: the reachability dial IS the connection we pipe (no throwaway probe).
			conn := dialCached(cfg, addr, edgePort(origin))
			if conn == nil {
				continue
			}
			dbg("route=direct %s:%d (%s)", addr, edgePort(origin), pathString(p))
			pipe(conn)
			return true
		}
		// relay chain: probe the entrypoint (the ssh child makes the real connection); r1..r(m-1)
		// are jump hosts and the last edge gives the target address (resolved on the last relay).
		if !reachable(cfg, addr, edgePort(origin)) {
			continue
		}
		dbg("route=chain %s", pathString(p))
		if err := runChain(cfg, self, p, addr); err == nil {
			return true
		} else {
			dbg("chain via %s failed: %v", addr, err)
		}
	}
	return false
}

func edgePort(e Edge) int {
	if e.Port == 0 {
		return 22
	}
	return e.Port
}

// chainPlan holds everything a relay chain needs: the generated ssh config, the `-W` target, and
// the alias of the last relay. buildChainPlan resolves it without any connection, so the debug
// mode can show the exact stanzas and target that runChain would use.
type chainPlan struct {
	sshConfig string
	target    string
	lastAlias string
}

// buildChainPlan renders a Host stanza per relay (ProxyJump-linked). r1Addr is the locally-resolved
// address of the first relay; every later relay's address is a literal resolved on its predecessor.
func buildChainPlan(cfg *Config, p []step, r1Addr string) (chainPlan, error) {
	// relays are the destinations of all steps except the last; the last step's edge addresses the target.
	relays := p[:len(p)-1]
	last := p[len(p)-1]

	var b strings.Builder
	for i, st := range relays {
		alias := fmt.Sprintf("kdnhop%d", i)
		host := r1Addr // first relay resolved locally (uplink/lan)
		if i > 0 {
			h, err := edgeLiteral(st.edge) // later relays: literal resolved on the previous hop
			if err != nil {
				return chainPlan{}, err
			}
			host = h
		}
		fmt.Fprintf(&b, "Host %s\n", alias)
		fmt.Fprintf(&b, "    HostName %s\n", host)
		fmt.Fprintf(&b, "    Port %d\n", edgePort(st.edge))
		fmt.Fprintf(&b, "    IdentityAgent SSH_AUTH_SOCK\n")
		if u := hostUser(cfg, st.dest); u != "" {
			fmt.Fprintf(&b, "    User %s\n", u)
		}
		if h, ok := cfg.Hosts[st.dest]; ok && h.HostKeyAlias != "" {
			fmt.Fprintf(&b, "    HostKeyAlias %s\n", h.HostKeyAlias)
		}
		if i > 0 {
			fmt.Fprintf(&b, "    ProxyJump kdnhop%d\n", i-1)
		}
		b.WriteString("\n")
	}

	targetAddr, err := edgeLiteral(last.edge)
	if err != nil {
		return chainPlan{}, err
	}
	return chainPlan{
		sshConfig: b.String(),
		target:    net.JoinHostPort(targetAddr, strconv.Itoa(edgePort(last.edge))),
		lastAlias: fmt.Sprintf("kdnhop%d", len(relays)-1),
	}, nil
}

// runChain writes the plan's ssh config to a per-invocation file and runs
// `ssh -F cfg -W <target>:<port> <lastRelay>` as a child.
func runChain(cfg *Config, self string, p []step, r1Addr string) error {
	plan, err := buildChainPlan(cfg, p, r1Addr)
	if err != nil {
		return err
	}

	dir := cacheDir()
	_ = os.MkdirAll(dir, 0o700)
	tmp, err := os.CreateTemp(dir, "chain-*.config")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(plan.sshConfig); err != nil {
		tmp.Close()
		return err
	}
	tmp.Close()

	sshPath, err := exec.LookPath("ssh")
	if err != nil {
		return err
	}
	target, lastAlias := plan.target, plan.lastAlias
	args := []string{"-F", tmp.Name(), "-o", "ConnectTimeout=5", "-W", target, lastAlias}
	dbg("run ssh %s (target %s via %s)", strings.Join(args, " "), target, pathString(p))
	cmd := exec.Command(sshPath, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func pipe(conn net.Conn) {
	// Copy stdin->conn in the background; on EOF half-close the write side. Copy conn->stdout in
	// the foreground, so the peer's full output drains before the close.
	go func() {
		io.Copy(conn, os.Stdin)
		if cw, ok := conn.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
	}()
	io.Copy(os.Stdout, conn)
	conn.Close()
}

// ---------- modes ----------

func modeProxy(cfg *Config, self string, args []string) {
	if len(args) < 1 {
		fatal("proxy: usage: proxy <ssh-host> [port]")
	}
	s := parseSpec(args[0])
	if _, ok := cfg.Hosts[s.host]; !ok {
		fatal("unknown host %q", s.host)
	}
	paths := filterPaths(findPaths(cfg, s.host), s)
	rankPaths(paths)
	if len(paths) == 0 {
		fatal("no route for %q (with the given tags)", s.host)
	}
	for _, p := range paths {
		if tryPath(cfg, self, p, s) {
			return
		}
	}
	fatal("no reachable route for %q", s.host)
}

func emitSSHConfig(cfg *Config, self, cfgPath string) string {
	var b strings.Builder
	names := make([]string, 0, len(cfg.Hosts))
	for n := range cfg.Hosts {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		h := cfg.Hosts[n]
		fmt.Fprintf(&b, "Host kdn-%s kdn-%s+*\n", n, n)
		if h.User != "" {
			fmt.Fprintf(&b, "    User %s\n", h.User)
		}
		if h.HostKeyAlias != "" {
			fmt.Fprintf(&b, "    HostKeyAlias %s\n", h.HostKeyAlias)
		}
		b.WriteString("\n")
	}
	b.WriteString("Host kdn-*\n")
	b.WriteString("    IdentityAgent SSH_AUTH_SOCK\n")
	if cfg.Defaults.IdentityFile != "" {
		fmt.Fprintf(&b, "    IdentityFile %s\n", cfg.Defaults.IdentityFile)
	}
	if cfg.Defaults.User != "" {
		fmt.Fprintf(&b, "    User %s\n", cfg.Defaults.User)
	}
	fmt.Fprintf(&b, "    ProxyCommand %s proxy --config %s %%h %%p\n\n", self, cfgPath)
	if len(cfg.IdentityAgentPatterns) > 0 {
		fmt.Fprintf(&b, "Host %s\n    IdentityAgent SSH_AUTH_SOCK\n", strings.Join(cfg.IdentityAgentPatterns, " "))
	}
	return b.String()
}

func modeSSH(cfg *Config, self, cfgPath string, args []string) {
	dir := cacheDir()
	_ = os.MkdirAll(dir, 0o700)
	dropin := filepath.Join(dir, "ssh_config")
	home, _ := os.UserHomeDir()
	content := emitSSHConfig(cfg, self, cfgPath) + "\nInclude " + filepath.Join(home, ".ssh", "config") + "\n"
	if err := os.WriteFile(dropin, []byte(content), 0o600); err != nil {
		fatal("write drop-in: %v", err)
	}
	sshPath, err := exec.LookPath("ssh")
	if err != nil {
		fatal("ssh not found: %v", err)
	}
	argv := append([]string{"ssh", "-F", dropin}, args...)
	if err := syscall.Exec(sshPath, argv, os.Environ()); err != nil {
		fatal("exec ssh: %v", err)
	}
}

func modeRoute(cfg *Config, args []string) {
	if len(args) < 1 {
		fatal("route: usage: route <ssh-host>")
	}
	s := parseSpec(args[0])
	if _, ok := cfg.Hosts[s.host]; !ok {
		fatal("unknown host %q", s.host)
	}
	paths := filterPaths(findPaths(cfg, s.host), s)
	rankPaths(paths)
	if len(paths) == 0 {
		fmt.Printf("(no paths to %s with the given tags)\n", s.host)
		return
	}
	for i, p := range paths {
		kind := "chain "
		if len(p) == 1 {
			kind = "direct"
		}
		fmt.Printf("%d. [prio %3d, %d hop] %s  %s\n", i+1, pathPriority(p), len(p), kind, pathString(p))
	}
}

// ---------- debug ----------

// The debug mode covers the known failure modes without opening an ssh session. It validates the
// graph, resolves every uplink and edge address, reports the reachability cache, probes only the
// first (local) hop, and prints the route and the ssh stanzas that a real run would use.

// report counts the verdicts of the debug checks and prints them as they happen.
type report struct {
	fails int
	warns int
}

func (r *report) section(title string)      { fmt.Printf("\n== %s ==\n", title) }
func (r *report) ok(f string, a ...any)     { fmt.Printf("  ok    "+f+"\n", a...) }
func (r *report) info(f string, a ...any)   { fmt.Printf("        "+f+"\n", a...) }
func (r *report) detail(f string, a ...any) { fmt.Printf("          "+f+"\n", a...) }

func (r *report) warn(f string, a ...any) {
	r.warns++
	fmt.Printf("  warn  "+f+"\n", a...)
}

func (r *report) fail(f string, a ...any) {
	r.fails++
	fmt.Printf("  FAIL  "+f+"\n", a...)
}

func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(strings.TrimPrefix(p, "~"), "/"))
		}
	}
	return p
}

// debugConfig reports the config source and its size.
func debugConfig(cfg *Config, cfgPath string, r *report) {
	r.section("config")
	r.ok("path %s", cfgPath)
	r.info("%d hosts, %d uplinks", len(cfg.Hosts), len(cfg.Uplinks))
	r.info("defaults: user=%q maxHops=%d probeTimeout=%dms cacheTtl=%ds ipPref=%s",
		cfg.Defaults.User, cfg.Defaults.MaxHops, cfg.Defaults.LanProbeTimeoutMs,
		cfg.Defaults.CacheTtlSeconds, cfg.Defaults.IPVersionPreference)
	if len(cfg.Hosts) == 0 {
		r.fail("the config declares no hosts")
	}
}

// debugGraph repeats the module.nix edge rules at run time (a hand-written or non-Nix config skips
// them), then reports every host that has no path from "me".
func debugGraph(cfg *Config, r *report) {
	r.section("graph")
	known := map[string]bool{"internet": true, "lan": true}
	for n := range cfg.Hosts {
		known[n] = true
	}
	names := sortedHostNames(cfg)
	bad := 0
	for _, hn := range names {
		h := cfg.Hosts[hn]
		if len(h.ReachedFrom) == 0 {
			r.warn("hosts.%s: no reachedFrom edges — the host is never reachable", hn)
			bad++
		}
		for i, e := range h.ReachedFrom {
			loc := fmt.Sprintf("hosts.%s.reachedFrom[%d]", hn, i)
			if !known[e.From] {
				r.fail(`%s: from=%q must be "internet", "lan", or a defined host`, loc, e.From)
				bad++
			}
			if e.From == hn {
				r.fail("%s: from=%q is the host itself", loc, e.From)
				bad++
			}
			if e.Address == "" && e.AddressFile == "" && e.Uplink == "" {
				r.fail("%s: needs address, addressFile, or uplink", loc)
				bad++
			}
			if e.Uplink != "" && e.From != "internet" {
				r.fail(`%s: uplink applies only to from="internet"`, loc)
				bad++
			}
			if e.Uplink != "" {
				if _, ok := cfg.Uplinks[e.Uplink]; !ok {
					r.fail("%s: unknown uplink %q", loc, e.Uplink)
					bad++
				}
			}
		}
	}
	if bad == 0 {
		r.ok("all %d hosts have valid edges", len(cfg.Hosts))
	}
	for _, hn := range names {
		if len(findPaths(cfg, hn)) == 0 {
			r.warn("no path me -> %s (check the edge origins, or raise defaults.maxHops=%d)",
				hn, cfg.Defaults.MaxHops)
		}
	}
}

// debugEnvironment checks what the ssh child needs: the ssh binary, the agent socket, and the
// identity file. A missing agent socket is the usual cause of an auth failure on a route that the
// probe reports as reachable.
func debugEnvironment(cfg *Config, r *report) {
	r.section("environment")
	if p, err := exec.LookPath("ssh"); err != nil {
		r.fail("ssh not on PATH: %v (relay chains and the `ssh` mode cannot run)", err)
	} else {
		r.ok("ssh %s", p)
	}
	if fp := netFingerprint(); fp == "nonet" {
		r.fail("no network: the routing table selects no source address for a default route")
	} else {
		r.ok("network fingerprint %s (local source address for a default route)", fp)
	}
	r.info("cache dir %s", cacheDir())

	sock := os.Getenv("SSH_AUTH_SOCK")
	switch {
	case sock == "":
		r.fail("SSH_AUTH_SOCK is unset — the emitted config pins IdentityAgent to it, so auth fails")
	default:
		if _, err := os.Stat(sock); err != nil {
			r.fail("SSH_AUTH_SOCK=%s is not usable: %v", sock, err)
		} else {
			r.ok("SSH_AUTH_SOCK %s", sock)
			debugAgentKeys(r)
		}
	}

	if cfg.Defaults.IdentityFile == "" {
		r.info("defaults.identityFile is unset — auth relies on the agent alone")
	} else if p := expandHome(cfg.Defaults.IdentityFile); func() bool { _, err := os.Stat(p); return err != nil }() {
		r.warn("defaults.identityFile %s does not exist", p)
	} else {
		r.ok("identityFile %s", p)
	}
}

// debugAgentKeys asks the agent for its identities. Exit code 1 means the agent holds no key.
func debugAgentKeys(r *report) {
	path, err := exec.LookPath("ssh-add")
	if err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, "-l").CombinedOutput()
	lines := 0
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.TrimSpace(l) != "" {
			lines++
		}
	}
	if err != nil {
		r.warn("ssh-add -l: %v (%s)", err, strings.TrimSpace(string(out)))
		return
	}
	r.detail("agent holds %d identity/identities", lines)
}

// debugUplinks resolves every uplink address, so a missing or empty WAN address file shows up here
// and not as an unexplained "no reachable route".
func debugUplinks(cfg *Config, r *report) {
	if len(cfg.Uplinks) == 0 {
		return
	}
	r.section("uplinks")
	names := make([]string, 0, len(cfg.Uplinks))
	for n := range cfg.Uplinks {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		u := cfg.Uplinks[n]
		r.info("%s:", n)
		for _, f := range []struct {
			label, lit, file string
		}{
			{"ipv6", u.IPv6, u.IPv6File},
			{"ipv4", u.IPv4, u.IPv4File},
		} {
			switch {
			case f.lit != "":
				r.detail("%s %s (literal)", f.label, f.lit)
			case f.file != "":
				if v, err := readFileValue(f.file); err != nil {
					r.warn("uplink %s.%sFile %s: %v", n, f.label, f.file, err)
				} else {
					r.detail("%s %s (from %s)", f.label, v, f.file)
				}
			}
		}
		if u.IPv4 == "" && u.IPv4File == "" && u.IPv6 == "" && u.IPv6File == "" {
			r.fail("uplink %s has no address at all", n)
		}
	}
}

// debugCache reports the cached reachability verdicts. A stale negative verdict makes a real run
// skip a route that is up again; --clear-cache removes it.
func debugCache(cfg *Config, r *report, cleared int) {
	r.section("reachability cache")
	if cleared > 0 {
		r.ok("cleared %d verdict(s) for this network", cleared)
	}
	mine, others := countVerdicts()
	r.info("%d verdict(s) for this network, %d for other networks (ttl %ds)",
		mine, others, cfg.Defaults.CacheTtlSeconds)
	r.info("clear with: kdn-ssh-access debug --clear-cache   (or rm -rf %s)",
		filepath.Join(cacheDir(), "reach"))
}

func sortedHostNames(cfg *Config) []string {
	names := make([]string, 0, len(cfg.Hosts))
	for n := range cfg.Hosts {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// debugHost diagnoses one host spec: it lists the paths that the tags drop and why, then walks the
// kept paths in rank order, resolves the entry addresses, probes the first hop, and shows the ssh
// stanzas for a chain. The first path with a reachable entry is the one a real run selects.
func debugHost(cfg *Config, arg string, r *report, timeout time.Duration, probe bool) {
	s := parseSpec(arg)
	r.section("host " + s.host)
	if _, ok := cfg.Hosts[s.host]; !ok {
		r.fail("unknown host %q — known: %s", s.host, strings.Join(sortedHostNames(cfg), " "))
		return
	}
	r.info("spec: host=%s direct=%v remote=%v via=%q family=%q",
		s.host, s.onlyDirect, s.onlyRemote, s.via, s.family)

	all := findPaths(cfg, s.host)
	if len(all) == 0 {
		r.fail("no path me -> %s in the graph (check edge origins, or defaults.maxHops=%d)",
			s.host, cfg.Defaults.MaxHops)
		return
	}
	var kept [][]step
	for _, p := range all {
		if reason := filterReason(p, s); reason != "" {
			r.info("dropped: %s  (%s)", pathString(p), reason)
		} else {
			kept = append(kept, p)
		}
	}
	if len(kept) == 0 {
		r.fail("all %d path(s) to %s are dropped by the tags", len(all), s.host)
		return
	}
	rankPaths(kept)
	r.ok("%d path(s) kept of %d", len(kept), len(all))

	selected := -1
	for i, p := range kept {
		kind := "chain"
		if len(p) == 1 {
			kind = "direct"
		}
		r.info("%d. [prio %3d, %d hop] %-6s %s", i+1, pathPriority(p), len(p), kind, pathString(p))

		origin := p[0].edge
		addrs, err := entryAddrs(cfg, origin, s.family)
		if err != nil {
			r.fail("path %d: entry address: %v", i+1, err)
			continue
		}
		for _, addr := range addrs {
			port := edgePort(origin)
			target := net.JoinHostPort(addr, strconv.Itoa(port))
			cachedVal, age, cacheKnown := readVerdict(target)
			cacheFresh := cacheKnown && age <= time.Duration(cfg.Defaults.CacheTtlSeconds)*time.Second
			if cacheKnown {
				note := "expired, a real run re-probes"
				if cacheFresh {
					note = "a real run honours this, not the probe below"
				}
				r.detail("cache %s -> %v (age %s, %s)", target, cachedVal, age.Truncate(time.Second), note)
			}
			if !probe {
				r.detail("entry %s (probe skipped)", target)
				if selected < 0 && !(cacheFresh && !cachedVal) {
					selected = i
				}
				continue
			}
			took, perr := probeFresh(addr, port, timeout)
			if perr != nil {
				r.detail("probe %s -> unreachable after %s: %v", target, took.Truncate(time.Microsecond), perr)
				continue
			}
			r.detail("probe %s -> ok in %s", target, took.Truncate(time.Microsecond))
			// A fresh negative verdict wins over the live probe: the real run skips this address
			// without a dial. This is the "debug says ok but ssh still fails" case.
			if cacheFresh && !cachedVal {
				r.warn("%s answers now, but a fresh cached verdict says unreachable — a real run skips it; use --clear-cache", target)
				continue
			}
			if len(p) > 1 {
				plan, perr := buildChainPlan(cfg, p, addr)
				if perr != nil {
					r.fail("path %d: relay address: %v", i+1, perr)
					continue
				}
				r.detail("would run: ssh -F <tmp> -o ConnectTimeout=5 -W %s %s", plan.target, plan.lastAlias)
				for _, l := range strings.Split(strings.TrimRight(plan.sshConfig, "\n"), "\n") {
					r.detail("  | %s", l)
				}
			}
			if selected < 0 {
				selected = i
			}
			break
		}
	}
	if selected < 0 {
		r.fail("no reachable route for %s — every entry address failed the probe", s.host)
		return
	}
	r.ok("a real run selects path %d: %s", selected+1, pathString(kept[selected]))
}

func modeDebug(cfg *Config, cfgPath string, args []string) {
	probe := true
	clear := false
	timeout := time.Duration(cfg.Defaults.LanProbeTimeoutMs) * time.Millisecond
	var hosts []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--no-probe" || a == "--config-only":
			probe = false
		case a == "--clear-cache":
			clear = true
		case a == "--timeout":
			if i+1 >= len(args) {
				fatal("--timeout needs a value in milliseconds")
			}
			ms, err := strconv.Atoi(args[i+1])
			if err != nil || ms <= 0 {
				fatal("--timeout: %q is not a positive number of milliseconds", args[i+1])
			}
			timeout = time.Duration(ms) * time.Millisecond
			i++
		case strings.HasPrefix(a, "-"):
			fatal("debug: unknown flag %q (--config-only|--no-probe|--clear-cache|--timeout <ms>)", a)
		default:
			hosts = append(hosts, a)
		}
	}

	cleared := 0
	if clear {
		cleared = clearVerdicts()
	}

	r := &report{}
	debugConfig(cfg, cfgPath, r)
	debugGraph(cfg, r)
	debugEnvironment(cfg, r)
	debugUplinks(cfg, r)
	debugCache(cfg, r, cleared)
	// Default to a reachability test of every host. Naming a host narrows the test; --config-only
	// (--no-probe) reduces it to the static checks and makes the run offline and instant.
	targets := hosts
	if len(targets) == 0 {
		targets = sortedHostNames(cfg)
	}
	for _, h := range targets {
		debugHost(cfg, h, r, timeout, probe)
	}

	fmt.Printf("\n== summary ==\n  %d failure(s), %d warning(s)\n", r.fails, r.warns)
	if r.fails > 0 {
		os.Exit(1)
	}
}

// ---------- main ----------

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fatal("usage: kdn-ssh-access <proxy|ssh|emit-ssh-config|route|debug> [--config <file>] ...")
	}
	mode := args[0]
	args = args[1:]

	cfgPath := os.Getenv("KDN_SSH_ACCESS_CONFIG")
	var rest []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--config":
			if i+1 >= len(args) {
				fatal("--config needs a value")
			}
			cfgPath = args[i+1]
			i++
		default:
			rest = append(rest, args[i])
		}
	}
	if cfgPath == "" {
		fatal("no config: pass --config <file> or set KDN_SSH_ACCESS_CONFIG")
	}
	cfg, err := loadConfig(cfgPath)
	if err != nil {
		fatal("%v", err)
	}
	self, err := os.Executable()
	if err != nil || self == "" {
		self = "kdn-ssh-access"
	}

	switch mode {
	case "proxy":
		modeProxy(cfg, self, rest)
	case "ssh":
		modeSSH(cfg, self, cfgPath, rest)
	case "emit-ssh-config":
		fmt.Print(emitSSHConfig(cfg, self, cfgPath))
	case "route":
		modeRoute(cfg, rest)
	case "debug":
		modeDebug(cfg, cfgPath, rest)
	default:
		fatal("unknown mode %q (proxy|ssh|emit-ssh-config|route|debug)", mode)
	}
}
