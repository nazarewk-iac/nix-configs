package secrets

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/lukasholzer/go-glob"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/exec"
)

type SecretStorage interface {
	Exists(path string) bool
	EncryptBytes(path string, data []byte) error
	Encrypt(path string, data string) error
	DecryptBytes(path string) ([]byte, error)
	Decrypt(path string) (string, error)
	List(subDir string) ([]string, error)
	UpdateKeys(subDir string) error
}

type sopsSecretStorage struct {
	BaseDir         string
	SecretsDir      string
	BaseDirSymlinks bool
	// TODO: clean up git repository from headers files
}

const (
	SopsPathSuffix = ".sops"
)

var _ SecretStorage = &sopsSecretStorage{}

func NewSopsSecretStorage(baseDir string) *sopsSecretStorage {
	return &sopsSecretStorage{
		BaseDir:    baseDir,
		SecretsDir: baseDir,
	}
}

func (s *sopsSecretStorage) WithSecretsDir(path string) *sopsSecretStorage {
	if !filepath.IsAbs(path) {
		path = filepath.Join(s.BaseDir, path)
	}
	s.SecretsDir = path
	return s
}

func (s *sopsSecretStorage) WithBaseDirSymlinks(value bool) *sopsSecretStorage {
	s.BaseDirSymlinks = value
	return s
}

func (s *sopsSecretStorage) toEncryptedPath(path string) string {
	path = filepath.Join(s.SecretsDir, path)
	if strings.Contains(filepath.Base(path), SopsPathSuffix) {
		return path
	}
	if ext := filepath.Ext(path); ext == "" {
		path = path + SopsPathSuffix
	} else {
		basePath := path[:len(path)-len(ext)]
		path = basePath + SopsPathSuffix + ext
	}

	return path
}

func (s *sopsSecretStorage) toDecryptedPath(path string) string {
	if newPath, err := filepath.Rel(s.SecretsDir, path); err == nil {
		path = newPath
	}
	if idx := strings.LastIndex(path, SopsPathSuffix); idx >= 0 {
		path = path[:idx] + path[idx+len(SopsPathSuffix):]
	}
	return path
}

func (s *sopsSecretStorage) Exists(path string) bool {
	stat, err := os.Stat(s.toEncryptedPath(path))
	if err != nil {
		return false
	}
	return stat.Mode().IsRegular()
}

func (s *sopsSecretStorage) EncryptBytes(path string, data []byte) (err error) {
	encryptedPath := s.toEncryptedPath(path)
	cmd := exec.LocalCommand("sops", "encrypt",
		"--filename-override", path,
		"--output", encryptedPath,
	)

	err = os.MkdirAll(filepath.Dir(encryptedPath), 0o750)
	if err != nil {
		return fmt.Errorf("secrets.EncryptBytes: creating directory for %s: %w", encryptedPath, err)
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("secrets.EncryptBytes: creating pipe: %w", err)
	}
	defer func() {
		err := stdin.Close()
		if err != nil && !strings.Contains(err.Error(), "file already closed") {
			slog.Error("EncryptBytes: failed to close stdin", "err", err)
		}
	}()
	if err = cmd.Start(); err != nil {
		return fmt.Errorf("secrets.EncryptBytes: command: start: %w", err)
	}
	if _, err = stdin.Write(data); err != nil {
		return fmt.Errorf("secrets.EncryptBytes: stdin: writing: %w", err)
	}
	if err = stdin.Close(); err != nil {
		return fmt.Errorf("secrets.EncryptBytes: stdin: closing: %w", err)
	}
	if err = cmd.Wait(); err != nil {
		return fmt.Errorf("secrets.EncryptBytes: command: wait: %w", err)
	}

	if s.BaseDirSymlinks && s.BaseDir != s.SecretsDir {
		baseDirPath := strings.Replace(encryptedPath, s.SecretsDir, s.BaseDir, 1)

		err = os.MkdirAll(filepath.Dir(baseDirPath), 0o750)
		if err != nil {
			return fmt.Errorf("secrets.EncryptBytes: creating directory for %v: %w", baseDirPath, err)
		}
		if err := os.Remove(baseDirPath); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("secrets.EncryptBytes: removing old symlink from %v: %w", baseDirPath, err)
		}
		symlinkPath, _ := filepath.Rel(filepath.Dir(baseDirPath), encryptedPath)
		if err := os.Symlink(symlinkPath, baseDirPath); err != nil {
			return fmt.Errorf("secrets.EncryptBytes: creating symlink from %v to %v: %w", baseDirPath, symlinkPath, err)
		}
	}

	return
}

func (s *sopsSecretStorage) Encrypt(path string, text string) (err error) {
	return s.EncryptBytes(path, []byte(text))
}

func (s *sopsSecretStorage) DecryptBytes(path string) ([]byte, error) {
	cmd := exec.LocalCommand("sops", "decrypt", s.toEncryptedPath(path))
	if data, err := cmd.Output(); err != nil {
		return data, fmt.Errorf("secrets.DecryptBytes: command result: %w", err)
	} else {
		return data, nil
	}
}

func (s *sopsSecretStorage) Decrypt(path string) (string, error) {
	data, err := s.DecryptBytes(path)
	return string(data), err
}

func (s *sopsSecretStorage) list(subDir string) ([]string, error) {
	if filepath.IsAbs(subDir) {
		if newDir, err := filepath.Rel(s.SecretsDir, subDir); err != nil {
			return nil, fmt.Errorf("sopsSecretStorage.list(%v): converting to relative path: %w", subDir, err)
		} else {
			subDir = newDir
		}
	}
	path := filepath.Join(s.SecretsDir, subDir)
	result := []string{}

	paths, err := glob.Glob(
		glob.CWD(path),
		glob.Pattern("**/*.sops*"),
		// not sure why it's required to be like that
		glob.IgnorePattern("**/.*/*"),
		&glob.Options{AbsolutePaths: true},
	)
	if err != nil {
		return nil, fmt.Errorf("sopsSecretStorage.list(%v): globbing: %w", subDir, err)
	}
paths:
	for _, path := range paths {
		for piece := range strings.SplitSeq(path, string(filepath.Separator)) {
			// drop out hidden file
			if strings.HasPrefix(piece, ".") {
				continue paths
			}
		}

		result = append(result, path)
	}

	return result, err
}

func (s *sopsSecretStorage) UpdateKeys(subDir string) error {
	paths, err := s.list(subDir)
	if err != nil {
		return fmt.Errorf("UpdateKeys(%v): listing directory: %w", subDir, err)
	}
	if len(paths) == 0 {
		return fmt.Errorf("UpdateKeys(%v): did not find any SOPS file", subDir)
	}
	args := []string{"sops", "updatekeys", "--yes"}
	args = append(args, paths...)
	if err := exec.LocalCommand(args...).Run(); err != nil {
		return fmt.Errorf("UpdateKeys(%v): rotating SOPS files: %w", subDir, err)
	}
	return nil
}

func (s *sopsSecretStorage) List(subDir string) ([]string, error) {
	var result []string
	paths, err := s.list(subDir)
	if err != nil {
		return paths, fmt.Errorf("List(%v): %w", subDir, err)
	}
	for _, path := range paths {
		result = append(result, s.toDecryptedPath(path))
	}

	return result, nil
}

func SopsList(dir string) ([]string, error) {
	s := NewSopsSecretStorage(dir)
	return s.List("")
}

func SopsUpdateKeys(dir string) error {
	s := NewSopsSecretStorage(dir)
	return s.UpdateKeys("")
}
