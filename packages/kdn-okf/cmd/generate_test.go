package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func generateFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"alpha.md":     "---\ntype: Note\ntitle: Alpha\ndescription: First concept\n---\n# Alpha\n",
		"beta.md":      "---\ntype: Note\ntitle: Beta\n---\n# Beta\n",
		"sub/gamma.md": "---\ntype: Note\ntitle: Gamma\n---\n# Gamma\n",
	}
	for rel, content := range files {
		path := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func generateApp(t *testing.T, root string) (*App, *bytes.Buffer) {
	t.Helper()
	var out bytes.Buffer
	return &App{
		Bundle:   root,
		CacheDir: t.TempDir(),
		Width:    100,
		Out:      &out,
		Err:      &out,
	}, &out
}

func TestGenerateIndexWritesAndIsIdempotent(t *testing.T) {
	root := generateFixture(t)
	app, out := generateApp(t, root)
	if err := app.generateIndex(false, false, false); err != nil {
		t.Fatal(err)
	}
	for _, rel := range []string{"index.md", "sub/index.md"} {
		data, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil {
			t.Fatalf("%s: %v", rel, err)
		}
		if !strings.Contains(string(data), generatedMarker) {
			t.Fatalf("%s has no generated marker:\n%s", rel, data)
		}
	}
	if !strings.Contains(out.String(), "2 directories: 2 written") {
		t.Fatalf("output has no summary:\n%s", out.String())
	}
	rootIndex, _ := os.ReadFile(filepath.Join(root, "index.md"))
	for _, want := range []string{"[Alpha](alpha.md)", "[Beta](beta.md)", "[sub](sub/index.md)", "First concept", "3 concepts"} {
		if !strings.Contains(string(rootIndex), want) {
			t.Fatalf("root index misses %q:\n%s", want, rootIndex)
		}
	}
	subIndex, _ := os.ReadFile(filepath.Join(root, "sub", "index.md"))
	if !strings.Contains(string(subIndex), "1 concept:") || !strings.Contains(string(subIndex), "[Gamma](gamma.md)") {
		t.Fatalf("sub index =\n%s", subIndex)
	}
	if err := app.generateIndex(false, false, false); err != nil {
		t.Fatal(err)
	}
	again, _ := os.ReadFile(filepath.Join(root, "index.md"))
	if string(again) != string(rootIndex) {
		t.Fatal("a second run changed the generated index")
	}
}

func TestGenerateIndexRefusesHumanFile(t *testing.T) {
	root := generateFixture(t)
	human := filepath.Join(root, "index.md")
	if err := os.WriteFile(human, []byte("# Hand written\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	app, out := generateApp(t, root)
	if err := app.generateIndex(false, false, false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "refuse") {
		t.Fatalf("output = %q", out.String())
	}
	data, _ := os.ReadFile(human)
	if string(data) != "# Hand written\n" {
		t.Fatalf("human index was overwritten:\n%s", data)
	}
	if err := app.generateIndex(false, true, false); err != nil {
		t.Fatal(err)
	}
	data, _ = os.ReadFile(human)
	if !strings.Contains(string(data), generatedMarker) {
		t.Fatalf("--force did not overwrite the human index:\n%s", data)
	}
}

func TestGenerateIndexCheck(t *testing.T) {
	root := generateFixture(t)
	app, _ := generateApp(t, root)
	err := app.generateIndex(false, false, true)
	if err == nil {
		t.Fatal("--check passed with missing indexes")
	}
	exit, ok := AsExitError(err)
	if !ok || exit.Code != 1 {
		t.Fatalf("error = %#v", err)
	}
	if err := app.generateIndex(false, false, false); err != nil {
		t.Fatal(err)
	}
	if err := app.generateIndex(false, false, true); err != nil {
		t.Fatalf("--check failed after generation: %v", err)
	}
	path := filepath.Join(root, "sub", "index.md")
	if err := os.WriteFile(path, []byte(generatedMarker+"\n# stale\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := app.generateIndex(false, false, true); err == nil {
		t.Fatal("--check passed with a stale generated index")
	}
}
