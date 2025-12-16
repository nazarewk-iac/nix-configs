package secrets

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestListSecrets(t *testing.T) {
	cwd := "/home/kdn/dev/github.com/nazarewk-iac/nix-configs"
	paths, err := SopsList(cwd)

	if len(paths) == 0 || err != nil {
		t.Errorf(`List() failed! cwd=%#v len=%d err=%v`, cwd, len(paths), err)
		return
	}
	t.Log("results:")
	for _, path := range paths {
		t.Logf("- %s", path)
		for piece := range strings.SplitSeq(path, string(filepath.Separator)) {
			if strings.HasPrefix(piece, ".") {
				t.Errorf(`List() matched a hidden file or directory! piece=%v path=%v`, piece, path)
			}
		}
	}
}

func TestPaths(t *testing.T) {
	s := NewSopsSecretStorage("/tmp").WithSecretsDir("sub")
	sourceToEncrypted := map[string]string{
		"data-pwet.key": "/tmp/sub/data-pwet.sops.key",
		"data":          "/tmp/sub/data.sops",
	}
	for decrypted, encrypted := range sourceToEncrypted {
		actualEncrypted := s.toEncryptedPath(decrypted)
		actualDecrypted := s.toDecryptedPath(actualEncrypted)

		if actualEncrypted != encrypted {
			t.Errorf("encrypted path %v does not equal expected path %v", actualEncrypted, encrypted)
		}

		if actualDecrypted != decrypted {
			t.Errorf("decrypted path %v does not equal source path %v", actualDecrypted, decrypted)
		}
	}
}
