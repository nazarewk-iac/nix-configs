package luks

import (
	"crypto/rand"
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"

	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/host"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/repo"
	"github.com/nazarewk-iac/nix-configs/tools/kdnctl/internal/secrets"
)

func KeyFileKey(h *host.Host, keyFileName string) string {
	return filepath.Join("hosts", h.Name, "luks", fmt.Sprintf("%s.key", keyFileName))
}

func EnsureLUKSKeyfilesForHost(r *repo.Repo, h *host.Host, s secrets.SecretStorage) error {
	config, err := h.GatherConfig(r)
	if err != nil {
		return fmt.Errorf("LUKS keyfile: gathering config: %w", err)
	}
	for _, entry := range config.LUKSVolumes {
		secretPath := KeyFileKey(h, entry.Name)
		if s.Exists(secretPath) {
			slog.Info("LUKS keyfile already exists, continuing", "host", h.Name, "name", entry.Name)
			continue
		}
		key := make([]byte, 2048)
		if _, e := rand.Read(key); e != nil {
			err = errors.Join(err, fmt.Errorf("LUKS keyfile: generating random data: %w", e))
			continue
		}
		if e := s.EncryptBytes(secretPath, key); e != nil {
			err = errors.Join(err, fmt.Errorf("LUKS keyfile: encrypting %s: %w", secretPath, e))
			continue
		}

		slog.Info("generated LUKS keyfile", "host", h.Name, "keyfile", entry.Name)
	}
	return err
}
