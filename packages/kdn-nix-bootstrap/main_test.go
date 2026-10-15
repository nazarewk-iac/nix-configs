package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeStep is one canned answer for one Run call, consumed in order.
type fakeStep struct {
	out string
	err error
}

// fakeExec records each call and replays canned answers in sequence. When the sequence is
// exhausted it returns an empty success, which reads as "the command worked".
type fakeExec struct {
	calls []string
	steps []fakeStep
}

func (f *fakeExec) Run(name string, args []string, stdin io.Reader) (string, error) {
	f.calls = append(f.calls, strings.TrimSpace(filepath.Base(name)+" "+strings.Join(args, " ")))
	if len(f.steps) == 0 {
		return "", nil
	}
	s := f.steps[0]
	f.steps = f.steps[1:]
	return s.out, s.err
}

func storeJSON(mount string) string {
	return fmt.Sprintf(`{"uuid":"B5B3-1","keychainService":"kdn-ext-store","mountPoint":%q}`, mount)
}

func writeConfigs(t *testing.T, store, job string) string {
	t.Helper()
	dir := t.TempDir()
	if store != "" {
		if err := os.WriteFile(filepath.Join(dir, storeConfigName), []byte(store), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if job != "" {
		if err := os.MkdirAll(filepath.Join(dir, jobsDirName), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, jobsDirName, "test.json"), []byte(job), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestLoadStoreConfigRejectsMissingFields(t *testing.T) {
	for _, body := range []string{
		`{}`,
		`{"uuid":"x","keychainService":"y"}`,
		`{"uuid":"x","mountPoint":"/nix"}`,
		`{"keychainService":"y","mountPoint":"/nix"}`,
		`{broken`,
	} {
		dir := writeConfigs(t, body, "")
		if _, err := loadStoreConfig(dir); err == nil {
			t.Errorf("loadStoreConfig(%s) returned no error", body)
		}
	}
}

func TestLoadJobConfig(t *testing.T) {
	dir := writeConfigs(t, storeJSON(t.TempDir()), `{"argv":["/bin/true"]}`)
	cfg, err := loadJobConfig(dir, "test")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.WaitPath != "/nix/store" {
		t.Errorf("WaitPath default = %q, want /nix/store", cfg.WaitPath)
	}
	if _, err := loadJobConfig(dir, "absent"); err == nil {
		t.Error("missing label must fail")
	}
	bad := writeConfigs(t, storeJSON(t.TempDir()), `{"argv":[]}`)
	if _, err := loadJobConfig(bad, "test"); err == nil {
		t.Error("empty argv must fail")
	}
}

func TestStoreMounted(t *testing.T) {
	mnt := t.TempDir()
	dir := writeConfigs(t, storeJSON(mnt), "")
	yes := &fakeExec{steps: []fakeStep{{out: fmt.Sprintf("/dev/disk7s2 on %s (apfs, local, nobrowse)\n", mnt)}}}
	state, err := storeMounted(dir, yes)
	if err != nil || !state {
		t.Errorf("mounted line: state=%v err=%v", state, err)
	}
	no := &fakeExec{steps: []fakeStep{{out: "/dev/disk3s1 on / (apfs, sealed, local)\n"}}}
	state, err = storeMounted(dir, no)
	if err != nil || state {
		t.Errorf("absent line: state=%v err=%v", state, err)
	}
}

func TestMountStoreIdempotentWhenMounted(t *testing.T) {
	mnt := t.TempDir()
	dir := writeConfigs(t, storeJSON(mnt), "")
	f := &fakeExec{steps: []fakeStep{{out: fmt.Sprintf("x on %s (apfs)\n", mnt)}}}
	if err := mountStore(dir, f, func(string, ...any) {}); err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 1 {
		t.Errorf("want only the mount check, got %v", f.calls)
	}
}

func TestMountStoreFullSequence(t *testing.T) {
	mnt := t.TempDir()
	dir := writeConfigs(t, storeJSON(mnt), "")
	f := &fakeExec{steps: []fakeStep{
		{out: ""},               // mount check: absent
		{out: "hunter2\n"},      // security
		{out: ""},               // unlock
		{out: ""},               // mount
		{out: "alreadyMounted"}, // storeMounted after? not called; keep spare
	}}
	if err := mountStore(dir, f, func(string, ...any) {}); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"mount",
		"security find-generic-password -s kdn-ext-store -w",
		"diskutil apfs unlockVolume B5B3-1 -stdinpassphrase",
		"diskutil mount -mountPoint " + mnt + " B5B3-1",
	}
	_ = want[3]
	if got := strings.Join(f.calls, "\n"); got != strings.Join(want, "\n") {
		t.Errorf("call sequence:\n got:\n%s\nwant:\n%s", got, strings.Join(want, "\n"))
	}
}

func TestMountStoreUsesUnlockUuidForPassphrase(t *testing.T) {
	mnt := t.TempDir()
	dir := writeConfigs(t, `{"uuid":"STORE-1","unlockUuid":"ANCHOR-2","keychainService":"ANCHOR-2","mountPoint":"`+mnt+`"}`, "")
	f := &fakeExec{steps: []fakeStep{
		{out: ""},
		{out: "pw\n"},
		{out: ""},
		{out: ""},
	}}
	if err := mountStore(dir, f, func(string, ...any) {}); err != nil {
		t.Fatal(err)
	}
	if f.calls[1] != "security find-generic-password -s ANCHOR-2 -w" || f.calls[2] != "diskutil apfs unlockVolume ANCHOR-2 -stdinpassphrase" {
		t.Errorf("unlock must use the anchor: %v", f.calls)
	}
	if f.calls[3] != "diskutil mount -mountPoint "+mnt+" STORE-1" {
		t.Errorf("mount must use the store uuid: %v", f.calls)
	}
}

func TestMountStoreUnlockToleratesAlreadyUnlocked(t *testing.T) {
	mnt := t.TempDir()
	dir := writeConfigs(t, storeJSON(mnt), "")
	f := &fakeExec{steps: []fakeStep{
		{out: ""},
		{out: "pw\n"},
		{out: "Error: -69671: The disk is already unlocked", err: errors.New("exit status 1")},
		{out: ""}, // mount succeeds
	}}
	if err := mountStore(dir, f, func(string, ...any) {}); err != nil {
		t.Fatalf("already-unlocked must be tolerated: %v", err)
	}
}

func TestMountStoreFailsOnMissingPassphrase(t *testing.T) {
	mnt := t.TempDir()
	dir := writeConfigs(t, storeJSON(mnt), "")
	f := &fakeExec{steps: []fakeStep{
		{out: ""},
		{out: "", err: errors.New("exit status 1")}, // security item absent
	}}
	if err := mountStore(dir, f, func(string, ...any) {}); err == nil {
		t.Fatal("missing keychain item must fail")
	}
}

func TestWaitPath(t *testing.T) {
	dir := t.TempDir()
	if err := waitPath(dir, time.Second); err != nil {
		t.Errorf("existing path: %v", err)
	}
	start := time.Now()
	if err := waitPath(filepath.Join(dir, "nope"), 3*time.Second); err == nil {
		t.Error("missing path must time out")
	} else if time.Since(start) < 2*time.Second {
		t.Error("timeout came too early")
	}
}
