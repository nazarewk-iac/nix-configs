// Package dag sorts the CA graph topologically.
//
// A root names no parent. An intermediate names its parent. A cycle and a parent that names no CA
// are hard errors. See design § 5.8.
package dag

import (
	"fmt"
	"sort"

	"kdn-certs/internal/decl"
)

// Sort returns the CA names in topological order: roots first, then each intermediate, then the
// deepest node. A cycle and a dangling parent are hard errors.
func Sort(cas decl.CAs) ([]string, error) {
	// A parent that names no CA is a hard error.
	for name, ca := range cas {
		if ca.Parent != nil && *ca.Parent != "" {
			if _, ok := cas[*ca.Parent]; !ok {
				return nil, fmt.Errorf("CA %q names parent %q, which is not declared", name, *ca.Parent)
			}
		}
	}

	// Depth of each node: a root is 0, a child is one more than its parent. A cycle makes the walk
	// revisit a node on the current path.
	const (
		unvisited = iota
		onPath
		done
	)
	state := map[string]int{}
	depth := map[string]int{}

	var visit func(name string) (int, error)
	visit = func(name string) (int, error) {
		switch state[name] {
		case onPath:
			return 0, fmt.Errorf("CA graph holds a cycle through %q", name)
		case done:
			return depth[name], nil
		}
		state[name] = onPath

		ca := cas[name]
		parentDepth := -1
		if ca.Parent != nil && *ca.Parent != "" {
			d, err := visit(*ca.Parent)
			if err != nil {
				return 0, err
			}
			parentDepth = d
		}
		depth[name] = parentDepth + 1
		state[name] = done
		return depth[name], nil
	}

	for name := range cas {
		if _, err := visit(name); err != nil {
			return nil, err
		}
	}

	names := make([]string, 0, len(cas))
	for name := range cas {
		names = append(names, name)
	}
	// Sort by depth, then by name, so the order is deterministic.
	sort.Slice(names, func(i, j int) bool {
		if depth[names[i]] != depth[names[j]] {
			return depth[names[i]] < depth[names[j]]
		}
		return names[i] < names[j]
	})
	return names, nil
}
