package secrets

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const (
	PathSuffix = ".sops"
)

func toEncryptedPath(path string) string {
	if strings.Contains(filepath.Base(path), PathSuffix) {
		return path
	}
	if ext := filepath.Ext(path); ext == "" {
		path = path + PathSuffix
	} else {
		basePath := path[:len(path)-len(ext)-1]
		path = basePath + PathSuffix + ext
	}

	return path
}

func toDecryptedPath(path string) string {
	if idx := strings.LastIndex(path, PathSuffix); idx >= 0 {
		path = path[:idx] + path[idx+len(PathSuffix):]
	}
	return path
}

func Exists(path string) bool {
	stat, err := os.Stat(toEncryptedPath(path))
	if err != nil {
		return false
	}
	return stat.Mode().IsRegular()
}

func EncryptBytes(path string, data []byte) (err error) {
	encryptedPath := toEncryptedPath(path)
	cmd := exec.Command("sops", "encrypt",
		"--filename-override", path,
		"--output", encryptedPath,
	)

	err = os.MkdirAll(filepath.Dir(encryptedPath), 0o750)
	if err != nil {
		return fmt.Errorf("error creating directory for %s: %w", encryptedPath, err)
	}
	cmd.Stderr = os.Stderr
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("cmd.StdinPipe() failed: %w", err)
	}
	closed := false
	defer func() {
		if !closed {
			stdin.Close()
		}
	}()
	cmd.Stderr = os.Stderr
	if err = cmd.Start(); err != nil {
		return fmt.Errorf("cmd.Start() failed: %w", err)
	}
	if _, err = stdin.Write(data); err != nil {
		return fmt.Errorf("stdin.Write() failed: %w", err)
	}
	if err = stdin.Close(); err != nil {
		return fmt.Errorf("cmd.Close() failed: %w", err)
	}
	if err = cmd.Wait(); err != nil {
		return fmt.Errorf("cmd.Wait() failed: %w", err)
	}

	return
}

func Encrypt(path string, text string) (err error) {
	return EncryptBytes(path, []byte(text))
}

func DecryptBytes(path string) ([]byte, error) {
	cmd := exec.Command("sops", "decrypt",
		"--filename-override", path,
		"--output", toEncryptedPath(path),
	)
	cmd.Stderr = os.Stderr
	return cmd.Output()
}

func Decrypt(path string) (string, error) {
	data, err := DecryptBytes(path)
	return string(data), err
}
