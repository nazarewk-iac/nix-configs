package dag

import (
	"reflect"
	"testing"

	"kdn-certs/internal/decl"
)

func ptr(s string) *string { return &s }

func TestSortRootsThenIntermediates(t *testing.T) {
	cas := decl.CAs{
		"leaf-ca": {
			Type:   "intermediate",
			Parent: ptr("root-ca"),
		},
		"root-ca": {
			Type: "root",
		},
		"deep-ca": {
			Type:   "intermediate",
			Parent: ptr("leaf-ca"),
		},
	}
	order, err := Sort(cas)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"root-ca", "leaf-ca", "deep-ca"}
	if !reflect.DeepEqual(order, want) {
		t.Errorf("Sort = %v, want %v", order, want)
	}
}

func TestSortCycleFails(t *testing.T) {
	cas := decl.CAs{
		"a": {Type: "intermediate", Parent: ptr("b")},
		"b": {Type: "intermediate", Parent: ptr("a")},
	}
	if _, err := Sort(cas); err == nil {
		t.Error("Sort(cycle) succeeded, want error")
	}
}

func TestSortDanglingParentFails(t *testing.T) {
	cas := decl.CAs{
		"a": {Type: "intermediate", Parent: ptr("missing")},
	}
	if _, err := Sort(cas); err == nil {
		t.Error("Sort(dangling parent) succeeded, want error")
	}
}

func TestSortDeterministic(t *testing.T) {
	cas := decl.CAs{
		"b": {Type: "root"},
		"a": {Type: "root"},
	}
	order, err := Sort(cas)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"a", "b"}
	if !reflect.DeepEqual(order, want) {
		t.Errorf("Sort = %v, want %v", order, want)
	}
}
