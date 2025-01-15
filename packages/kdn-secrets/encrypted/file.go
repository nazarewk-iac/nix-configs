package encrypted

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"github.com/nazarewk-iac/nix-configs/packages/kdn-secrets/paths"
	"io"
	"iter"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
)

type File struct {
	Path     string
	Resolved string
}

func (f *File) Name() string {
	return filepath.Base(f.Name())
}

// CalculateChecksum calculates all (prefixed) files checksums, so one can just create a new one alongside executable
func (f *File) CalculateChecksum() (checksum string, err error) {
	hash := sha256.New()
	matches, err := filepath.Glob(fmt.Sprintf("%s.*", f.Path))
	if err != nil {
		return
	}
	buf := make([]byte, 4096)
	for _, file := range matches {
		fc, err := os.Open(file)
		if err != nil {
			return checksum, err
		}
		n, err := fc.Read(buf)
		if err == io.EOF {
			continue
		} else if err != nil {
			return checksum, err
		}
		hash.Write(buf[:n])
	}
	checksum = hex.EncodeToString(hash.Sum(nil))
	return
}

func IterEncrypted(searchDirs []string) iter.Seq2[*File, error] {
	return func(yield func(*File, error) bool) {
		found := map[string]struct{}{}
		for _, configDir := range searchDirs {
			matches, err := os.ReadDir(configDir)
			if os.IsNotExist(err) || os.IsPermission(err) {
				continue
			} else if err != nil {
				if !yield(nil, err) {
					return
				}
				continue
			}

			for _, match := range matches {
				if match.IsDir() {
					continue
				}
				if strings.Contains(filepath.Base(match.Name()), ".") {
					slog.Debug("skipping file", "file", match.Name(), "reason", "contains a dot in the name")
					continue
				}
				target, err := filepath.EvalSymlinks(match.Name())
				if os.IsNotExist(err) || os.IsPermission(err) {
					continue
				} else if err != nil {
					if !yield(nil, err) {
						return
					}
					continue
				}
				if _, ok := found[target]; ok {
					continue
				}
				found[target] = struct{}{}
				if !paths.CanRead(target) {
					slog.Debug("skipping file", "file", match.Name(), "reason", "is not readable")
					continue
				}
				if paths.CanExecute(target) {
					if !yield(&File{
						Path:     match.Name(),
						Resolved: target,
					}, nil) {
						return
					}
				} else {
					slog.Warn("found a file which is not an executable", "file", match.Name())
				}
			}
		}
	}
}
