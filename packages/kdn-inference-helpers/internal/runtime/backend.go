// Package runtime wires the pieces the binary needs: the backend the control plane calls, which
// combines the engine supervisor, the privileged cache-drop hook and the llama-swap client.
package runtime

import (
	"context"
	"fmt"
	"os/exec"
	"time"

	"kdn-inference-helpers/internal/config"
	"kdn-inference-helpers/internal/engine"
	"kdn-inference-helpers/internal/swap"
)

// Backend implements control.Backend: start, stop, drop caches, unload companions, list models.
type Backend struct {
	Supervisor *engine.Supervisor
	Swap       *swap.Client
	Cfg        *config.Config
}

// StartEngine prepares and launches one profile through the adapter.
func (b *Backend) StartEngine(ctx context.Context, profile string) (time.Duration, error) {
	return b.Supervisor.Start(ctx, profile)
}

// StopEngine terminates the engine this runtime owns and the one it does not.
func (b *Backend) StopEngine(ctx context.Context) (time.Duration, error) {
	return b.Supervisor.Stop(ctx)
}

// DropCaches runs the deployment's privileged hook. An empty hook means the engine does not need it
// and the phase is skipped, which is the right answer for any engine whose loads do not depend on
// the page cache being released.
func (b *Backend) DropCaches(ctx context.Context) (time.Duration, error) {
	start := time.Now()
	if len(b.Cfg.CacheDropCommand) == 0 {
		return 0, nil
	}
	cmd := exec.CommandContext(ctx, b.Cfg.CacheDropCommand[0], b.Cfg.CacheDropCommand[1:]...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return time.Since(start), fmt.Errorf("cache drop: %w: %s", err, string(out))
	}
	return time.Since(start), nil
}

// UnloadCompanions unloads every loaded model that is not a frontier id. That is what frees the
// companion's VRAM before the engine stops.
func (b *Backend) UnloadCompanions(ctx context.Context) ([]string, error) {
	loaded, err := b.Swap.Loaded(ctx)
	if err != nil {
		return nil, err
	}
	var unloaded []string
	for _, id := range loaded {
		if b.Cfg.IsFrontier(id) {
			continue
		}
		if err := b.Swap.Unload(ctx, id); err != nil {
			return unloaded, err
		}
		unloaded = append(unloaded, id)
	}
	return unloaded, nil
}

// LoadedModels is llama-swap's view, used by `/unload` and by the companion watcher.
func (b *Backend) LoadedModels(ctx context.Context) ([]string, error) {
	return b.Swap.Loaded(ctx)
}

// Profiles is the adapter's table.
func (b *Backend) Profiles() []string { return b.Supervisor.Adapter.Profiles() }

// EngineReady reports whether the engine answers right now.
func (b *Backend) EngineReady() bool {
	return b.Supervisor.Ready(context.Background())
}
