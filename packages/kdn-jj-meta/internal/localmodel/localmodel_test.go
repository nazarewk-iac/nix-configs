package localmodel

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestABareAliasGetsTheCurrentProfile(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"profile":"max","draining":false}`))
	}))
	defer srv.Close()

	got := Resolve([]string{"qfn"}, env(map[string]string{"KDN_INFERENCE_MANAGER_URL": srv.URL}))
	if len(got) != 1 || got[0] != "qfn=max" {
		t.Fatalf("resolved = %v", got)
	}
}

// The profile the caller names wins: a change made while `max` was current but described as
// `qfn=omni-fast` is the caller's record, not ours to rewrite.
func TestAnExplicitProfileIsKept(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"profile":"max"}`))
	}))
	defer srv.Close()

	got := Resolve(
		[]string{"qfn=omni-fast", "qwen-image-edit=image-qwen (Qwen-Image-Edit-2511 Q4_K_M)"},
		env(map[string]string{"KDN_INFERENCE_MANAGER_URL": srv.URL}),
	)
	want := []string{"qfn=omni-fast", "qwen-image-edit=image-qwen (Qwen-Image-Edit-2511 Q4_K_M)"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("resolved = %v", got)
	}
}

// A commit must not fail because the serving host is asleep.
func TestAnUnreachableManagerLeavesTheAliasAlone(t *testing.T) {
	got := Resolve([]string{"qfn"}, env(map[string]string{
		"KDN_INFERENCE_MANAGER_URL": "http://127.0.0.1:1",
	}))
	if len(got) != 1 || got[0] != "qfn" {
		t.Fatalf("resolved = %v", got)
	}
}

func TestTheEnvDefaultIsCommaSeparated(t *testing.T) {
	got := FromEnv(env(map[string]string{"KDN_JJ_META_LOCAL_MODELS": "qfn, qwen3-omni ,"}))
	if strings.Join(got, "|") != "qfn|qwen3-omni" {
		t.Fatalf("env list = %v", got)
	}
	if FromEnv(env(nil)) != nil {
		t.Fatal("an unset variable produced a list")
	}
}
