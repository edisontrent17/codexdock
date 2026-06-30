package config_test

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/config"
)

func TestSaveLoadAndRegisterMachine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	store := config.NewStore(path)

	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	err := cfg.UpsertMachine("personal", config.Machine{
		Name:    "homepc",
		Host:    "homepc.tailnet",
		SSHUser: "manoj",
		SSHPort: 22,
		Role:    "codex-host",
	})
	require.NoError(t, err)

	require.NoError(t, store.Save(cfg))

	loaded, err := store.Load()
	require.NoError(t, err)
	got, err := loaded.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "homepc", got.Name)
	require.Equal(t, "homepc.tailnet", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
	require.Equal(t, 22, got.SSHPort)
	require.Equal(t, "codex-host", got.Role)
}

func TestSaveLoadNetworkProfileMetadata(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	store := config.NewStore(path)
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{
		Name:       "personal",
		Role:       "controller",
		ControlURL: "https://control.example",
	})

	require.NoError(t, store.Save(cfg))

	loaded, err := store.Load()
	require.NoError(t, err)
	network := loaded.Networks["personal"]
	require.Equal(t, "controller", network.Role)
	require.Equal(t, "https://control.example", network.ControlURL)
}

func TestRegisterRejectsDuplicateMachineAlias(t *testing.T) {
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{Name: "homepc", SSHUser: "manoj"}))

	err := cfg.UpsertMachine("personal", config.Machine{Name: "homepc", SSHUser: "other"})

	require.ErrorContains(t, err, "already exists")
}

func TestResolveMachineReportsMissingNetworkAndMachine(t *testing.T) {
	cfg := config.New()

	_, err := cfg.ResolveMachine("personal", "homepc")
	require.ErrorContains(t, err, "network personal not found")

	cfg.UpsertNetwork(config.Network{Name: "personal"})
	_, err = cfg.ResolveMachine("personal", "homepc")
	require.ErrorContains(t, err, "machine homepc not found")
}
