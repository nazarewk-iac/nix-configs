package repo

import "path/filepath"

type Repo struct {
	Root   string
	Remote string
}

func New(root string, remote string) *Repo {
	return &Repo{
		Root:   root,
		Remote: remote,
	}
}

func (r *Repo) GetHostDir(hostName string) string {
	return filepath.Join(r.Root, "hosts", hostName)
}
