package index

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeFile(t *testing.T, root, rel, content string) {
	t.Helper()
	path := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func fixtureBundle(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	writeFile(t, root, "index.md", "---\ntype: Index\n---\n# Index\n")
	writeFile(t, root, "alpha.md", "---\ntype: Note\ntitle: Alpha\n---\n# Alpha\n\n[beta](/beta.md)\n[missing](missing.md)\n")
	writeFile(t, root, "beta.md", "---\ntype: Note\ntitle: Beta\n---\n# Beta\n\n[alpha](alpha.md)\n")
	writeFile(t, root, "sub/gamma.md", "---\ntype: Note\ntitle: Gamma\n---\n# Gamma\n\n[alpha](../alpha.md)\n")
	writeFile(t, root, ".hidden/secret.md", "---\ntype: Note\n---\n# Secret\n")
	writeFile(t, root, ".board.md", "---\ntype: Board\n---\n")
	return root
}

func TestLoadBundle(t *testing.T) {
	root := fixtureBundle(t)
	cache := t.TempDir()
	now := time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	result, err := Load(Options{Root: root, CacheDir: cache, Now: now})
	if err != nil {
		t.Fatal(err)
	}
	if got := len(result.Bundle.Concepts); got != 3 {
		t.Fatalf("concepts = %d, want 3", got)
	}
	if got := len(result.Bundle.Reserved); got != 1 {
		t.Fatalf("reserved = %d, want 1", got)
	}
	alpha := result.Bundle.Find("alpha")
	if alpha == nil {
		t.Fatal("alpha not found")
	}
	if got := len(alpha.Backlinks); got != 2 {
		t.Errorf("alpha backlinks = %d, want 2", got)
	}
	if got := len(alpha.Links); got != 2 {
		t.Fatalf("alpha links = %d", got)
	}
	if !alpha.Links[1].Missing {
		t.Errorf("missing link not flagged: %#v", alpha.Links[1])
	}
	if result.Bundle.Find("sub/gamma") == nil {
		t.Errorf("sub/gamma not indexed")
	}
	if result.Bundle.Find("secret") != nil {
		t.Errorf("hidden directory was indexed")
	}
	if result.Bundle.Find("board") != nil {
		t.Errorf("hidden file was indexed")
	}

	warm, err := Load(Options{Root: root, CacheDir: cache, Now: now})
	if err != nil {
		t.Fatal(err)
	}
	if !warm.Cache.Warm {
		t.Errorf("second load was not warm")
	}
	rebuilt, err := Load(Options{Root: root, CacheDir: cache, Now: now, Rebuild: true})
	if err != nil {
		t.Fatal(err)
	}
	if rebuilt.Cache.Warm {
		t.Errorf("--rebuild used the cache")
	}
}

func TestMissingBacklinksAndOrphans(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "a.md", "---\ntype: Note\n---\n# A\n\n[b](b.md)\n")
	writeFile(t, root, "b.md", "---\ntype: Note\n---\n# B\n")
	writeFile(t, root, "c.md", "---\ntype: Note\n---\n# C\n")
	result, err := Load(Options{Root: root, CacheDir: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	missing := MissingBacklinks(result.Bundle.Concepts)
	found := false
	for _, issue := range missing {
		if issue.Code == "missing-backlink" {
			found = true
		}
	}
	if !found {
		t.Errorf("missing-backlink not reported: %#v", missing)
	}
	orphans := Orphans(result.Bundle.Concepts)
	if len(orphans) != 2 {
		t.Errorf("orphans = %d, want 2 (b and c)", len(orphans))
	}
}
