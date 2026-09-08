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
// `debug` is the entry point when a connection fails. It validates the graph, resolves the uplink
// and edge addresses, checks the ssh binary and the agent, reports the reachability cache, probes
// the first hop, and then — unless you pass --no-connect — opens a real ssh session to every host
// in scope and runs `true` there. That session is the only check that covers authentication, the
// host keys, and every hop after the first. See README.md.
package main

import (
	"bytes"
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

// recordRoute logs the selected route, and appends it to the file that $KDN_SSH_ACCESS_ROUTE_FILE
// names. The `debug` mode reads that file, because ssh sends the ProxyCommand stderr to /dev/null
// unless ssh itself runs verbose — so the log line alone never reaches the parent.
func recordRoute(line string) {
	dbg("route=%s", line)
	path := os.Getenv("KDN_SSH_ACCESS_ROUTE_FILE")
	if path == "" {
		return
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintln(f, line)
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
			recordRoute(fmt.Sprintf("direct %s (%s)",
				net.JoinHostPort(addr, strconv.Itoa(edgePort(origin))), pathString(p)))
			pipe(conn)
			return true
		}
		// relay chain: probe the entrypoint (the ssh child makes the real connection); r1..r(m-1)
		// are jump hosts and the last edge gives the target address (resolved on the last relay).
		if !reachable(cfg, addr, edgePort(origin)) {
			continue
		}
		recordRoute("chain " + pathString(p))
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

// The debug mode walks the same decision path as a real run: it validates the graph, resolves every
// address, probes the first hop, and then opens a real ssh session to each host in scope. The
// session is the only check that reaches authentication, the host keys, and the hops after the
// first. `--no-connect` drops back to the static, tap-free form.
//
// The output is a summary. Each -v adds one level of detail: -v the ranked paths and the resolved
// addresses, -vv the probes, the ssh stanzas, and the raw ssh stderr, -vvv ssh's own -v trace.

// report counts the verdicts of the debug checks and prints them at the current verbosity.
type report struct {
	fails int
	warns int
	v     int
}

func (r *report) head(title string)       { fmt.Printf("\n== %s ==\n", title) }
func (r *report) ok(f string, a ...any)   { fmt.Printf("  ok    "+f+"\n", a...) }
func (r *report) skip(f string, a ...any) { fmt.Printf("  skip  "+f+"\n", a...) }
func (r *report) line(f string, a ...any) { fmt.Printf("        "+f+"\n", a...) }

func (r *report) warn(f string, a ...any) {
	r.warns++
	fmt.Printf("  warn  "+f+"\n", a...)
}

func (r *report) fail(f string, a ...any) {
	r.fails++
	fmt.Printf("  FAIL  "+f+"\n", a...)
}

// info prints at -v and detail at -vv, so the default run stays one line per check.
func (r *report) info(f string, a ...any) {
	if r.v >= 1 {
		fmt.Printf("        "+f+"\n", a...)
	}
}

func (r *report) detail(f string, a ...any) {
	if r.v >= 2 {
		fmt.Printf("          "+f+"\n", a...)
	}
}

func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(strings.TrimPrefix(p, "~"), "/"))
		}
	}
	return p
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// debugConfig reports the config source and its size.
func debugConfig(cfg *Config, cfgPath string, r *report) {
	if len(cfg.Hosts) == 0 {
		r.fail("config    %s declares no hosts", cfgPath)
		return
	}
	r.ok("config    %d host(s), %d uplink(s) — %s", len(cfg.Hosts), len(cfg.Uplinks), cfgPath)
	r.info("defaults: user=%q maxHops=%d probeTimeout=%dms cacheTtl=%ds ipPref=%s",
		cfg.Defaults.User, cfg.Defaults.MaxHops, cfg.Defaults.LanProbeTimeoutMs,
		cfg.Defaults.CacheTtlSeconds, cfg.Defaults.IPVersionPreference)
}

// debugGraph repeats the module.nix edge rules at run time (a hand-written or non-Nix config skips
// them), then reports every host that has no path from "me".
func debugGraph(cfg *Config, r *report) {
	known := map[string]bool{"internet": true, "lan": true}
	for n := range cfg.Hosts {
		known[n] = true
	}
	names := sortedHostNames(cfg)
	bad := 0
	for _, hn := range names {
		h := cfg.Hosts[hn]
		if len(h.ReachedFrom) == 0 {
			r.warn("graph     hosts.%s: no reachedFrom edges — the host is never reachable", hn)
			bad++
		}
		for i, e := range h.ReachedFrom {
			loc := fmt.Sprintf("hosts.%s.reachedFrom[%d]", hn, i)
			if !known[e.From] {
				r.fail(`graph     %s: from=%q must be "internet", "lan", or a defined host`, loc, e.From)
				bad++
			}
			if e.From == hn {
				r.fail("graph     %s: from=%q is the host itself", loc, e.From)
				bad++
			}
			if e.Address == "" && e.AddressFile == "" && e.Uplink == "" {
				r.fail("graph     %s: needs address, addressFile, or uplink", loc)
				bad++
			}
			if e.Uplink != "" && e.From != "internet" {
				r.fail(`graph     %s: uplink applies only to from="internet"`, loc)
				bad++
			}
			if e.Uplink != "" {
				if _, ok := cfg.Uplinks[e.Uplink]; !ok {
					r.fail("graph     %s: unknown uplink %q", loc, e.Uplink)
					bad++
				}
			}
		}
	}
	for _, hn := range names {
		if len(findPaths(cfg, hn)) == 0 {
			r.warn("graph     no path me -> %s (check the edge origins, or raise defaults.maxHops=%d)",
				hn, cfg.Defaults.MaxHops)
			bad++
		}
	}
	if bad == 0 {
		r.ok("graph     all %d host(s) have valid edges and a path from me", len(cfg.Hosts))
	}
}

// debugEnvironment checks what the ssh child needs: the ssh binary, the agent socket, and the
// identity file. A missing agent socket is the usual cause of an auth failure on a route that the
// probe reports as reachable.
func debugEnvironment(cfg *Config, r *report) {
	var notes []string
	// The verdict line prints first, so the -v detail lines stay under it.
	var infos []string
	add := func(f string, a ...any) { infos = append(infos, fmt.Sprintf(f, a...)) }

	if p, err := exec.LookPath("ssh"); err != nil {
		r.fail("env       ssh not on PATH: %v (no relay chain and no session can run)", err)
	} else {
		notes = append(notes, "ssh ok")
		add("ssh %s", p)
	}
	if fp := netFingerprint(); fp == "nonet" {
		r.fail("env       no network: the routing table selects no source address for a default route")
	} else {
		notes = append(notes, "net "+fp)
	}
	sock := os.Getenv("SSH_AUTH_SOCK")
	switch {
	case sock == "":
		r.fail("env       SSH_AUTH_SOCK is unset — the emitted config pins IdentityAgent to it, so auth fails")
	case !fileExists(sock):
		r.fail("env       SSH_AUTH_SOCK=%s does not exist", sock)
	default:
		add("SSH_AUTH_SOCK %s", sock)
		switch n, err := agentKeyCount(); {
		case err != nil:
			r.warn("env       ssh-add -l: %v", err)
		case n == 0:
			r.warn("env       the agent holds no identity — publickey auth cannot work")
		default:
			notes = append(notes, fmt.Sprintf("agent %d key(s)", n))
		}
	}
	if cfg.Defaults.IdentityFile == "" {
		add("defaults.identityFile is unset — auth relies on the agent alone")
	} else if p := expandHome(cfg.Defaults.IdentityFile); !fileExists(p) {
		r.warn("env       defaults.identityFile %s does not exist", p)
	} else {
		add("identityFile %s", p)
	}
	if len(notes) > 0 {
		r.ok("env       %s", strings.Join(notes, ", "))
	}
	for _, i := range infos {
		r.info("%s", i)
	}
	r.info("cache dir %s", cacheDir())
}

// agentKeyCount asks the agent for its identities. Exit code 1 means the agent holds no key.
func agentKeyCount() (int, error) {
	path, err := exec.LookPath("ssh-add")
	if err != nil {
		return 0, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, "-l").CombinedOutput()
	n := 0
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.TrimSpace(l) != "" {
			n++
		}
	}
	if err != nil {
		if n == 1 && strings.Contains(string(out), "no identities") {
			return 0, nil
		}
		return 0, fmt.Errorf("%v (%s)", err, strings.TrimSpace(string(out)))
	}
	return n, nil
}

// debugUplinks resolves every uplink address, so a missing or empty WAN address file shows up here
// and not as an unexplained "no reachable route".
func debugUplinks(cfg *Config, r *report) {
	if len(cfg.Uplinks) == 0 {
		return
	}
	names := make([]string, 0, len(cfg.Uplinks))
	for n := range cfg.Uplinks {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		u := cfg.Uplinks[n]
		if u.IPv4 == "" && u.IPv4File == "" && u.IPv6 == "" && u.IPv6File == "" {
			r.fail("uplinks   %s has no address at all", n)
			continue
		}
		var got, infos []string
		for _, f := range []struct {
			label, lit, file string
		}{
			{"ipv6", u.IPv6, u.IPv6File},
			{"ipv4", u.IPv4, u.IPv4File},
		} {
			switch {
			case f.lit != "":
				got = append(got, f.label+" "+f.lit)
				infos = append(infos, fmt.Sprintf("uplink %s.%s %s (literal)", n, f.label, f.lit))
			case f.file != "":
				if v, err := readFileValue(f.file); err != nil {
					r.warn("uplinks   %s.%sFile %s: %v", n, f.label, f.file, err)
				} else {
					got = append(got, f.label+" "+v)
					infos = append(infos, fmt.Sprintf("uplink %s.%s %s (from %s)", n, f.label, v, f.file))
				}
			}
		}
		if len(got) > 0 {
			r.ok("uplinks   %s: %s", n, strings.Join(got, ", "))
		}
		for _, i := range infos {
			r.info("%s", i)
		}
	}
}

// debugCache reports the cached reachability verdicts. A stale negative verdict makes a real run
// skip a route that is up again; --clear-cache removes it.
func debugCache(cfg *Config, r *report, cleared int) {
	if cleared > 0 {
		r.ok("cache     cleared %d verdict(s) for this network", cleared)
	}
	mine, others := countVerdicts()
	r.line("cache     %d verdict(s) for this network, %d for other networks (ttl %ds)",
		mine, others, cfg.Defaults.CacheTtlSeconds)
	r.info("clear with --clear-cache, or rm -rf %s", filepath.Join(cacheDir(), "reach"))
}

func sortedHostNames(cfg *Config) []string {
	names := make([]string, 0, len(cfg.Hosts))
	for n := range cfg.Hosts {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// hostCheck is what the static stage learned about one host spec. The connect stage reuses it, so
// it only opens a session to a host that has a reachable entry address.
type hostCheck struct {
	arg      string
	spec     spec
	paths    [][]step // kept, ranked
	selected int      // index into paths; -1 = no reachable entry
	entry    string   // host:port of the entry address a real run dials
	probed   int      // entry addresses probed
}

// debugHost diagnoses one host spec: it lists the paths that the tags drop and why, then walks the
// kept paths in rank order, resolves the entry addresses, probes the first hop, and shows the ssh
// stanzas for a chain. The first path with a reachable entry is the one a real run selects.
func debugHost(cfg *Config, arg string, r *report, timeout time.Duration, probe bool) hostCheck {
	s := parseSpec(arg)
	hc := hostCheck{arg: arg, spec: s, selected: -1}
	if _, ok := cfg.Hosts[s.host]; !ok {
		r.fail("%-9s unknown host — known: %s", s.host, strings.Join(sortedHostNames(cfg), " "))
		return hc
	}
	r.info("%s: spec direct=%v remote=%v via=%q family=%q",
		s.host, s.onlyDirect, s.onlyRemote, s.via, s.family)

	all := findPaths(cfg, s.host)
	if len(all) == 0 {
		r.fail("%-9s no path in the graph (check the edge origins, or defaults.maxHops=%d)",
			s.host, cfg.Defaults.MaxHops)
		return hc
	}
	var kept [][]step
	for _, p := range all {
		if reason := filterReason(p, s); reason != "" {
			r.detail("dropped %s (%s)", pathString(p), reason)
		} else {
			kept = append(kept, p)
		}
	}
	if len(kept) == 0 {
		r.fail("%-9s all %d path(s) dropped by the tags", s.host, len(all))
		return hc
	}
	rankPaths(kept)
	hc.paths = kept
	ttl := time.Duration(cfg.Defaults.CacheTtlSeconds) * time.Second

	for i, p := range kept {
		kind := "chain"
		if len(p) == 1 {
			kind = "direct"
		}
		r.info("%s: path %d/%d [prio %3d, %d hop] %-6s %s",
			s.host, i+1, len(kept), pathPriority(p), len(p), kind, pathString(p))

		origin := p[0].edge
		addrs, err := entryAddrs(cfg, origin, s.family)
		if err != nil {
			r.fail("%-9s path %d entry address: %v", s.host, i+1, err)
			continue
		}
		for _, addr := range addrs {
			port := edgePort(origin)
			target := net.JoinHostPort(addr, strconv.Itoa(port))
			cachedVal, age, cacheKnown := readVerdict(target)
			cacheFresh := cacheKnown && age <= ttl
			if cacheKnown {
				note := "expired, a real run re-probes"
				if cacheFresh {
					note = "a real run honours this, not the probe below"
				}
				r.detail("cache %s -> %v (age %s, %s)", target, cachedVal, age.Truncate(time.Second), note)
			}
			if !probe {
				r.detail("entry %s (probe skipped)", target)
				if hc.selected < 0 && !(cacheFresh && !cachedVal) {
					hc.selected, hc.entry = i, target
				}
				continue
			}
			hc.probed++
			took, perr := probeFresh(addr, port, timeout)
			if perr != nil {
				r.detail("probe %s -> unreachable after %s: %v", target, took.Truncate(time.Millisecond), perr)
				continue
			}
			r.detail("probe %s -> ok in %s", target, took.Truncate(time.Millisecond))
			// A fresh negative verdict wins over the live probe: the real run skips this address
			// without a dial. This is the "debug says ok but ssh still fails" case.
			if cacheFresh && !cachedVal {
				r.warn("%-9s %s answers now, but a fresh cached verdict says unreachable — a real run skips it; use --clear-cache",
					s.host, target)
				continue
			}
			if len(p) > 1 {
				plan, perr := buildChainPlan(cfg, p, addr)
				if perr != nil {
					r.fail("%-9s path %d relay address: %v", s.host, i+1, perr)
					continue
				}
				r.detail("would run: ssh -F <tmp> -o ConnectTimeout=5 -W %s %s", plan.target, plan.lastAlias)
				for _, l := range strings.Split(strings.TrimRight(plan.sshConfig, "\n"), "\n") {
					r.detail("  | %s", l)
				}
			}
			if hc.selected < 0 {
				hc.selected, hc.entry = i, target
			}
			break
		}
	}
	if hc.selected < 0 {
		if !probe {
			r.warn("%-9s every entry address holds a fresh negative verdict — use --clear-cache", s.host)
		} else {
			r.fail("%-9s no reachable entry (%d path(s), %d address(es) probed)", s.host, len(kept), hc.probed)
		}
		return hc
	}
	p := kept[hc.selected]
	hops := "1 hop"
	if len(p) > 1 {
		hops = fmt.Sprintf("%d hops", len(p))
	}
	// Without a probe the selection is a prediction, so it gets no verdict mark.
	if !probe {
		r.line("%-9s path %d/%d  %s  (prio %d, %s, entry %s, unprobed)",
			s.host, hc.selected+1, len(kept), pathString(p), pathPriority(p), hops, hc.entry)
		return hc
	}
	r.ok("%-9s path %d/%d  %s  (prio %d, %s, entry %s)",
		s.host, hc.selected+1, len(kept), pathString(p), pathPriority(p), hops, hc.entry)
	return hc
}

// ---------- debug: the real session ----------

// connectBanner states what the session stage does before it does it, and how to opt out.
func connectBanner(r *report, n int) {
	r.line("A real ssh session to %d host(s), each running `true` on arrival. Every session:", n)
	r.line("  - can ask for a hardware-key tap;")
	r.line("  - writes the reachability cache, like any real run;")
	r.line("  - fails on an unknown host key, because BatchMode allows no prompt.")
	r.line("Opt out with:")
	r.line("  --no-connect     static checks and TCP probes only — no session, no tap")
	r.line("  --config-only    static checks only — offline and instant")
	r.line("  debug <host>...  narrow the run to the hosts you name")
}

// sessionDropIn writes the same ssh drop-in that the `ssh` mode writes, so a session goes through
// the real ProxyCommand and reports what a real run does, not a prediction of it.
func sessionDropIn(cfg *Config, self, cfgPath string) (string, error) {
	dir := cacheDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "debug_ssh_config")
	home, _ := os.UserHomeDir()
	content := emitSSHConfig(cfg, self, cfgPath) + "\nInclude " + filepath.Join(home, ".ssh", "config") + "\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		return "", err
	}
	return path, nil
}

// readRouteFile returns the last route the ProxyCommand recorded, or "" when it recorded none.
func readRouteFile(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	used := ""
	for _, l := range strings.Split(string(b), "\n") {
		if t := strings.TrimSpace(l); t != "" {
			used = t
		}
	}
	return used
}

// sshErrorLine returns the last line of ssh's stderr that is not our own log, and a hint when the
// message names a known cause.
func sshErrorLine(stderr string) (string, string) {
	last := ""
	for _, l := range strings.Split(stderr, "\n") {
		t := strings.TrimSpace(l)
		if t == "" || strings.HasPrefix(t, "kdn-ssh-access:") || strings.HasPrefix(t, "debug1:") {
			continue
		}
		last = t
	}
	hints := []struct{ needle, hint string }{
		{"Host key verification failed", "compare `emit-ssh-config` with ~/.ssh/known_hosts — a hostKeyAlias changed, or two hosts share one alias"},
		{"Permission denied", "wrong `user` for that host, or the agent holds no key the host accepts"},
		{"Name or service not known", "the relay cannot resolve the target address of the last edge — that name resolves ON the relay"},
		{"Could not resolve hostname", "the relay cannot resolve the target address of the last edge — that name resolves ON the relay"},
		{"Connection timed out", "the entry hop answered, but a later hop did not — check the relay edge addresses"},
		{"Connection closed", "the entry hop answered, then the connection broke — check the last hop and the sshd on the target"},
		{"Operation timed out", "the entry hop answered, but a later hop did not — check the relay edge addresses"},
	}
	for _, h := range hints {
		if strings.Contains(stderr, h.needle) {
			return last, h.hint
		}
	}
	return last, ""
}

// sshStderr keeps ssh's stderr for the report, and forwards it live when the level asks for it. It
// always forwards a line that asks the user for something: a hardware-key tap prompt is useless
// after the fact, and without it the token only blinks.
type sshStderr struct {
	all     *bytes.Buffer
	partial []byte
	passAll bool
}

func (w *sshStderr) Write(p []byte) (int, error) {
	w.all.Write(p)
	w.partial = append(w.partial, p...)
	for {
		i := bytes.IndexByte(w.partial, '\n')
		if i < 0 {
			break
		}
		w.emit(string(w.partial[:i]))
		w.partial = w.partial[i+1:]
	}
	// A prompt often arrives with no newline, so forward the tail as soon as it asks for something.
	if len(w.partial) > 0 && isPrompt(string(w.partial)) {
		w.emit(string(w.partial))
		w.partial = nil
	}
	return len(p), nil
}

func (w *sshStderr) emit(line string) {
	line = strings.TrimRight(line, "\r")
	if strings.TrimSpace(line) == "" {
		return
	}
	if w.passAll || isPrompt(line) {
		fmt.Fprintf(os.Stderr, "          | %s\n", line)
	}
}

// flush forwards a last partial line, so nothing is lost when ssh writes no final newline.
func (w *sshStderr) flush() {
	if len(w.partial) > 0 {
		w.emit(string(w.partial))
		w.partial = nil
	}
}

// isPrompt is true for the lines that need the user to act.
func isPrompt(line string) bool {
	l := strings.ToLower(line)
	for _, n := range []string{"user presence", "enter pin", "pin for", "touch", "confirm", "passphrase"} {
		if strings.Contains(l, n) {
			return true
		}
	}
	return false
}

// debugConnectHost opens the session for one host and reports the outcome.
func debugConnectHost(sshPath, dropin string, hc hostCheck, r *report, timeout time.Duration, sshVerbose bool) {
	alias := "kdn-" + strings.TrimPrefix(hc.arg, "kdn-")
	connectSecs := int(timeout.Seconds())
	if connectSecs > 10 {
		connectSecs = 10
	}
	args := []string{"-F", dropin, "-o", "BatchMode=yes", "-o", fmt.Sprintf("ConnectTimeout=%d", connectSecs)}
	if sshVerbose {
		args = append(args, "-v")
	}
	args = append(args, alias, "true")
	r.info("%s: ssh %s", hc.spec.host, strings.Join(args, " "))

	// The ProxyCommand records the route it took into this file. Its stderr goes nowhere that we
	// can read, so the file is the only way to learn what ssh really did.
	routeFile := filepath.Join(cacheDir(), "debug_route_"+hc.spec.host)
	_ = os.Remove(routeFile)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	var errbuf bytes.Buffer
	// -vv forwards every line live. Below that only the prompts pass, so the report stays short.
	w := &sshStderr{all: &errbuf, passAll: r.v >= 2}
	cmd := exec.CommandContext(ctx, sshPath, args...)
	cmd.Env = append(os.Environ(), "KDN_SSH_ACCESS_DEBUG=1", "KDN_SSH_ACCESS_ROUTE_FILE="+routeFile)
	cmd.Stdout = io.Discard
	cmd.Stderr = w
	// Nothing prints while ssh runs, so a tap wait looks like a freeze. An agent that holds a
	// touch-required key signs in its own process, and its "Confirm user presence" line never
	// reaches this stderr — so say it here instead.
	waiting := time.AfterFunc(2*time.Second, func() {
		r.line("%s: no answer yet — a hardware key may want a tap", hc.spec.host)
	})
	start := time.Now()
	err := cmd.Run()
	took := time.Since(start).Truncate(time.Millisecond)
	waiting.Stop()
	w.flush()
	stderr := errbuf.String()

	used := readRouteFile(routeFile)
	_ = os.Remove(routeFile)
	suffix := ""
	if used != "" {
		suffix = " — ssh used " + used
	}
	switch {
	case err == nil:
		r.ok("%-9s session ok in %s, `true` exited 0%s", hc.spec.host, took, suffix)
	case ctx.Err() == context.DeadlineExceeded:
		r.fail("%-9s no answer within %s — raise it with --connect-timeout <s>%s", hc.spec.host, timeout, suffix)
	default:
		msg, hint := sshErrorLine(stderr)
		if msg == "" {
			msg = err.Error()
		}
		r.fail("%-9s session failed after %s: %s%s", hc.spec.host, took, msg, suffix)
		if hint != "" {
			r.line("          hint: %s", hint)
		}
		if r.v < 2 {
			r.line("          -vv prints ssh's full stderr")
		}
	}
}

func modeDebug(cfg *Config, self, cfgPath string, args []string) {
	probe := true
	connect := true
	clear := false
	verbosity := 0
	timeout := time.Duration(cfg.Defaults.LanProbeTimeoutMs) * time.Millisecond
	connectTimeout := 30 * time.Second
	var hosts []string
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "--no-probe" || a == "--config-only":
			probe = false
			connect = false
		case a == "--no-connect":
			connect = false
		case a == "--connect":
			connect = true
		case a == "--clear-cache":
			clear = true
		case a == "--verbose" || a == "--details":
			verbosity++
		case len(a) > 1 && a[0] == '-' && a[1] != '-' && strings.Trim(a[1:], "v") == "":
			verbosity += len(a) - 1
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
		case a == "--connect-timeout":
			if i+1 >= len(args) {
				fatal("--connect-timeout needs a value in seconds")
			}
			s, err := strconv.Atoi(args[i+1])
			if err != nil || s <= 0 {
				fatal("--connect-timeout: %q is not a positive number of seconds", args[i+1])
			}
			connectTimeout = time.Duration(s) * time.Second
			i++
		case strings.HasPrefix(a, "-"):
			fatal("debug: unknown flag %q (-v|-vv|-vvv|--details|--no-connect|--config-only|--clear-cache|--timeout <ms>|--connect-timeout <s>)", a)
		default:
			hosts = append(hosts, a)
		}
	}

	cleared := 0
	if clear {
		cleared = clearVerdicts()
	}

	r := &report{v: verbosity}
	r.head("checks")
	debugConfig(cfg, cfgPath, r)
	debugGraph(cfg, r)
	debugEnvironment(cfg, r)
	debugUplinks(cfg, r)
	debugCache(cfg, r, cleared)

	// Default to every host in the graph. Naming a host narrows the run; --config-only
	// (--no-probe) reduces it to the static checks and makes the run offline and instant.
	targets := hosts
	if len(targets) == 0 {
		targets = sortedHostNames(cfg)
	}
	r.head("routes")
	checks := make([]hostCheck, 0, len(targets))
	for _, h := range targets {
		checks = append(checks, debugHost(cfg, h, r, timeout, probe))
	}

	r.head("session")
	switch {
	case !connect && !probe:
		r.skip("--config-only: no probe and no session — the addresses, the auth, the host keys, and every hop after the first stay untested")
	case !connect:
		r.skip("--no-connect: the auth, the host keys, and every hop after the first stay untested")
	default:
		var live []hostCheck
		for _, hc := range checks {
			if hc.selected >= 0 {
				live = append(live, hc)
			}
		}
		if len(live) == 0 {
			r.skip("no host has a reachable entry address — there is nothing to connect to")
			break
		}
		sshPath, err := exec.LookPath("ssh")
		if err != nil {
			r.fail("session   ssh not on PATH: %v", err)
			break
		}
		dropin, err := sessionDropIn(cfg, self, cfgPath)
		if err != nil {
			r.fail("session   write the drop-in config: %v", err)
			break
		}
		connectBanner(r, len(live))
		r.info("drop-in %s", dropin)
		for _, hc := range live {
			debugConnectHost(sshPath, dropin, hc, r, connectTimeout, verbosity >= 3)
		}
		for _, hc := range checks {
			if hc.selected < 0 {
				r.skip("%-9s no reachable entry address — no session", hc.spec.host)
			}
		}
	}

	r.head("summary")
	r.line("%d host(s) in scope, %d failure(s), %d warning(s)", len(targets), r.fails, r.warns)
	switch {
	case !probe:
		r.line("no probe and no session ran: this run proves the config and the graph only")
	case !connect:
		r.line("no session ran: a reachable entry address is all this run proves")
	}
	if r.v == 0 {
		r.line("-v adds the ranked paths and the resolved addresses, -vv the probes and the ssh")
		r.line("stanzas, -vvv ssh's own -v trace")
	}
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
		modeDebug(cfg, self, cfgPath, rest)
	default:
		fatal("unknown mode %q (proxy|ssh|emit-ssh-config|route|debug)", mode)
	}
}
