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
// Modes: proxy <host> <port> | ssh [args...] | emit-ssh-config | route <host>.
// The host arg is `kdn-<name>[+tag]...`; tags: direct, remote, via=<host>, 4, 6.
package main

import (
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

func filterPaths(paths [][]step, s spec) [][]step {
	var out [][]step
	for _, p := range paths {
		// +direct keeps LAN-origin paths; +remote keeps internet-origin paths (the WAN entry or a
		// relay chain). The first edge's origin is always "lan" or "internet".
		if s.onlyDirect && !(len(p) >= 1 && p[0].edge.From == "lan") {
			continue
		}
		if s.onlyRemote && !(len(p) >= 1 && p[0].edge.From == "internet") {
			continue
		}
		if s.via != "" {
			found := false
			for _, st := range p {
				if st.dest == s.via {
					found = true
					break
				}
			}
			if !found {
				continue
			}
		}
		out = append(out, p)
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

// runChain writes a per-invocation ssh config with a Host stanza per relay (ProxyJump-linked) and
// runs `ssh -F cfg -W <target>:<port> <lastRelay>` as a child. r1Addr is the locally-resolved
// address of the first relay; every later relay's address is a literal resolved on its predecessor.
func runChain(cfg *Config, self string, p []step, r1Addr string) error {
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
				return err
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

	dir := cacheDir()
	_ = os.MkdirAll(dir, 0o700)
	tmp, err := os.CreateTemp(dir, "chain-*.config")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(b.String()); err != nil {
		tmp.Close()
		return err
	}
	tmp.Close()

	sshPath, err := exec.LookPath("ssh")
	if err != nil {
		return err
	}
	lastAlias := fmt.Sprintf("kdnhop%d", len(relays)-1)
	targetAddr, err := edgeLiteral(last.edge)
	if err != nil {
		return err
	}
	target := net.JoinHostPort(targetAddr, strconv.Itoa(edgePort(last.edge)))
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

// ---------- main ----------

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fatal("usage: kdn-ssh-access <proxy|ssh|emit-ssh-config|route> [--config <file>] ...")
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
	default:
		fatal("unknown mode %q (proxy|ssh|emit-ssh-config|route)", mode)
	}
}
