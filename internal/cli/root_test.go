package cli_test

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/cli"
	"github.com/trentsoftware/codexdock/internal/config"
	"github.com/trentsoftware/codexdock/internal/control"
	"github.com/trentsoftware/codexdock/internal/ssh"
	"github.com/trentsoftware/codexdock/internal/tailnet"
	"github.com/trentsoftware/codexdock/internal/version"
)

func TestCreateAndRegisterCommandsPersistState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{"register", "homepc", "personal", "--host", "100.64.0.2", "--ssh-user", "manoj"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := cfg.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "homepc", got.Name)
	require.Equal(t, "100.64.0.2", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
}

func TestInitCreatesNetworkAndMachineProfile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{
		"init",
		"--network", "personal",
		"--machine", "homepc",
		"--host", "homepc",
		"--ssh-user", "manoj",
		"--ssh-port", "2222",
		"--workspace", "~/src/codexdock",
		"--session", "codex",
		"--agent", "codex --ask",
		"--control-url", "https://control.example",
		"--role", "codex-host",
	})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "personal", cfg.CurrentNetwork)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
	machine, err := cfg.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "homepc", machine.Host)
	require.Equal(t, "manoj", machine.SSHUser)
	require.Equal(t, 2222, machine.SSHPort)
	require.Equal(t, "~/src/codexdock", machine.Workspace)
	require.Equal(t, "codex", machine.SessionName)
	require.Equal(t, "codex --ask", machine.AgentCommand)
	require.Equal(t, "codex-host", machine.Role)
	require.Contains(t, out.String(), "Initialized homepc in personal")
	require.Contains(t, out.String(), "codexdock doctor homepc personal")
}

func TestInitTrimsControlURLBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"init",
		"--network", "personal",
		"--machine", "homepc",
		"--host", "homepc",
		"--ssh-user", "manoj",
		"--control-url", "  https://control.example  ",
	})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
}

func TestInitRejectsBlankControlURLBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"init",
		"--network", "personal",
		"--machine", "homepc",
		"--host", "homepc",
		"--ssh-user", "manoj",
		"--control-url", "   ",
	})
	err := root.Execute()

	require.ErrorContains(t, err, "--control-url cannot be blank")
	require.NoFileExists(t, path)
}

func TestInitRejectsBlankNetworkAndMachineAliasesBeforeSaving(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr string
	}{
		{
			name:    "network",
			args:    []string{"--network", "   ", "--machine", "homepc"},
			wantErr: "--network cannot be blank",
		},
		{
			name:    "machine",
			args:    []string{"--network", "personal", "--machine", "   "},
			wantErr: "--machine cannot be blank",
		},
		{
			name:    "device",
			args:    []string{"--network", "personal", "--device", "   "},
			wantErr: "--device cannot be blank",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.yaml")
			root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})
			args := append([]string{"init", "--host", "100.64.0.2", "--ssh-user", "manoj"}, tc.args...)

			root.SetArgs(args)
			err := root.Execute()

			require.ErrorContains(t, err, tc.wantErr)
			require.NoFileExists(t, path)
		})
	}
}

func TestInitDeviceDefaultsToPersonalNetwork(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{
		"init",
		"--device", "windows-wsl",
		"--host", "100.64.0.2",
		"--ssh-user", "lakshmi",
		"--workspace", "~/code",
		"--session", "codex",
		"--agent", "codex",
	})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "personal", cfg.CurrentNetwork)
	machine, err := cfg.ResolveMachine("personal", "windows-wsl")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.2", machine.Host)
	require.Equal(t, "lakshmi", machine.SSHUser)
	require.Equal(t, "~/code", machine.Workspace)
	require.Contains(t, out.String(), "Initialized windows-wsl in personal")
}

func TestInitRejectsNonPositiveSSHPort(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"init", "--network", "personal", "--machine", "homepc", "--host", "100.64.0.2", "--ssh-user", "manoj", "--ssh-port", "0"})
	err := root.Execute()

	require.ErrorContains(t, err, "--ssh-port must be positive")
	require.NoFileExists(t, path)
}

func TestInitRejectsInvalidSessionName(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"init", "--network", "personal", "--machine", "homepc", "--host", "100.64.0.2", "--ssh-user", "manoj", "--session", "bad session"})
	err := root.Execute()

	require.ErrorContains(t, err, "invalid tmux session name")
	require.NoFileExists(t, path)
}

func TestInitRejectsBlankAgentAndWorkspace(t *testing.T) {
	for _, tc := range []struct {
		name    string
		args    []string
		wantErr string
	}{
		{name: "agent", args: []string{"--agent", "   "}, wantErr: "--agent cannot be empty"},
		{name: "workspace", args: []string{"--workspace", "   "}, wantErr: "--workspace cannot be empty"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.yaml")
			root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})
			args := append([]string{"init", "--network", "personal", "--machine", "homepc", "--host", "100.64.0.2", "--ssh-user", "manoj"}, tc.args...)

			root.SetArgs(args)
			err := root.Execute()

			require.ErrorContains(t, err, tc.wantErr)
			require.NoFileExists(t, path)
		})
	}
}

func TestInitRejectsInvalidNetworkRole(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"init", "--network", "personal", "--network-role", "edge", "--machine", "homepc", "--host", "100.64.0.2", "--ssh-user", "manoj"})
	err := root.Execute()

	require.ErrorContains(t, err, "--network-role must be client or controller")
	require.NoFileExists(t, path)
}

func TestInitRejectsDeviceAndMachineTogether(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"init", "--device", "windows-wsl", "--machine", "homepc", "--host", "100.64.0.2", "--ssh-user", "manoj"})
	err := root.Execute()

	require.ErrorContains(t, err, "use either --machine or --device")
}

func TestInitRefusesExistingMachineWithoutForce(t *testing.T) {
	path := seedConfig(t)
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"init", "--network", "personal", "--machine", "homepc", "--host", "newhost", "--ssh-user", "manoj"})
	err := root.Execute()

	require.ErrorContains(t, err, "homepc already exists")
	require.ErrorContains(t, err, "--force")
}

func TestInitForceReplacesExistingMachine(t *testing.T) {
	path := seedConfig(t)
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"init", "--network", "personal", "--machine", "homepc", "--host", "newhost", "--ssh-user", "lakshmi", "--ssh-port", "2222", "--force"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	machine, err := cfg.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "newhost", machine.Host)
	require.Equal(t, "lakshmi", machine.SSHUser)
	require.Equal(t, 2222, machine.SSHPort)
}

func TestCreateStoresNetworkProfileAndPrintsJoinGuidance(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--role", "controller", "--control-url", "https://control.example"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	network := cfg.Networks["personal"]
	require.Equal(t, "controller", network.Role)
	require.Equal(t, "https://control.example", network.ControlURL)
	require.Contains(t, out.String(), "Invite another machine:")
	require.Contains(t, out.String(), "codexdock invite personal")
	require.NotContains(t, out.String(), "codexdock register <machine> personal --control-url https://control.example\n")
}

func TestCreateTrimsControlURLBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--control-url", "  https://control.example  "})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
}

func TestCreateRejectsBlankControlURLBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--control-url", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "--control-url cannot be blank")
	require.NoFileExists(t, path)
}

func TestCreateRejectsBlankNetworkNameBeforeProvision(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	issuer := &fakeControlIssuer{installed: true}
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "   ", "--provision"})
	err := root.Execute()

	require.ErrorContains(t, err, "network name cannot be blank")
	require.Empty(t, issuer.networks)
	require.NoFileExists(t, path)
}

func TestCreateProvisionCreatesControllerNetworkBeforeSavingProfile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	issuer := &fakeControlIssuer{installed: true}
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--role", "controller", "--control-url", "https://control.example", "--provision"})
	require.NoError(t, root.Execute())

	require.Equal(t, []control.NetworkOptions{{Name: "personal"}}, issuer.networks)
	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "controller", cfg.Networks["personal"].Role)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
	require.Contains(t, out.String(), "Provisioned network personal")
}

func TestCreateRejectsInvalidRoleBeforeProvision(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	issuer := &fakeControlIssuer{installed: true}
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--role", "edge", "--provision"})
	err := root.Execute()

	require.ErrorContains(t, err, "--role must be client or controller")
	require.Empty(t, issuer.networks)
	require.NoFileExists(t, path)
}

func TestCreateRefusesDuplicateNetworkWithoutForce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{"create", "personal", "--role", "controller"})
	err := root.Execute()

	require.ErrorContains(t, err, "network personal already exists")
	require.ErrorContains(t, err, "--force")
	cfg, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	require.Equal(t, "client", cfg.Networks["personal"].Role)
}

func TestCreateForceUpdatesNetworkProfileAndPreservesMachines(t *testing.T) {
	path := seedConfig(t)
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--role", "controller", "--control-url", "https://control.example", "--force"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	network := cfg.Networks["personal"]
	require.Equal(t, "controller", network.Role)
	require.Equal(t, "https://control.example", network.ControlURL)
	require.Contains(t, network.Machines, "homepc")
}

func TestCreateProvisionDoesNotProvisionDuplicateLocalNetwork(t *testing.T) {
	path := seedConfig(t)
	issuer := &fakeControlIssuer{installed: true}
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal", "--provision"})
	err := root.Execute()

	require.ErrorContains(t, err, "network personal already exists")
	require.Empty(t, issuer.networks)
}

func TestRegisterCanSetNetworkControlURL(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{"register", "homepc", "personal", "--control-url", "https://control.example", "--ssh-user", "manoj"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
}

func TestRegisterJoinTrimsControlURLBeforeSavingAndJoining(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{
		installed:    true,
		joinRecorder: &joins,
		status: tailnet.Status{
			Self: tailnet.Peer{HostName: "macbook", IP: "100.64.0.10", Online: true},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{
		"register", "macbook", "personal",
		"--control-url", "  https://control.example  ",
		"--ssh-user", "manoj",
		"--join",
	})
	require.NoError(t, root.Execute())

	require.Equal(t, []tailnet.JoinOptions{{
		ControlURL: "https://control.example",
		Hostname:   "macbook",
	}}, joins)
	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
}

func TestRegisterJoinRejectsBlankStoredControlURLBeforeJoin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "   "})
	require.NoError(t, config.NewStore(path).Save(cfg))
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{installed: true, joinRecorder: &joins}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"register", "macbook", "personal", "--ssh-user", "manoj", "--join"})
	err := root.Execute()

	require.ErrorContains(t, err, "control URL is required to join network personal")
	require.Empty(t, joins)
}

func TestRegisterUsesCurrentNetworkWhenOmitted(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{"register", "homepc", "--host", "100.64.0.2", "--ssh-user", "manoj"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := cfg.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "homepc", got.Name)
	require.Equal(t, "100.64.0.2", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
}

func TestRegisterJoinUsesManagedPrivateNetworkClient(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{
		installed:    true,
		joinRecorder: &joins,
		status: tailnet.Status{
			Self: tailnet.Peer{HostName: "macbook", IP: "100.64.0.10", Online: true},
		},
	}
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{
		"register", "macbook", "personal",
		"--control-url", "https://control.example",
		"--ssh-user", "manoj",
		"--join",
		"--enrollment-key", "tskey-auth",
	})
	require.NoError(t, root.Execute())

	require.Equal(t, []tailnet.JoinOptions{{
		ControlURL: "https://control.example",
		AuthKey:    "tskey-auth",
		Hostname:   "macbook",
	}}, joins)
	require.Contains(t, out.String(), "Joined macbook to personal")
	require.NotContains(t, out.String(), "tskey-auth")

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := cfg.ResolveMachine("personal", "macbook")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.10", got.Host)
}

func TestRegisterJoinRejectsBlankEnrollmentKeyBeforeJoin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "https://control.example"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{installed: true, joinRecorder: &joins}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"register", "macbook", "personal",
		"--ssh-user", "manoj",
		"--join",
		"--enrollment-key", "   ",
	})
	err := root.Execute()

	require.ErrorContains(t, err, "--enrollment-key cannot be blank")
	require.Empty(t, joins)
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "macbook")
	require.ErrorContains(t, resolveErr, "machine macbook not found")
}

func TestRegisterRejectsBlankMachineNameBeforeJoin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "https://control.example"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{installed: true, joinRecorder: &joins}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"register", "   ", "personal",
		"--ssh-user", "manoj",
		"--join",
	})
	err := root.Execute()

	require.ErrorContains(t, err, "machine name cannot be blank")
	require.Empty(t, joins)
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	require.Empty(t, loaded.Networks["personal"].Machines)
}

func TestRegisterJoinRejectsBlankNetworkNameBeforeJoin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{installed: true, joinRecorder: &joins}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"register", "macbook", "   ",
		"--control-url", "https://control.example",
		"--ssh-user", "manoj",
		"--join",
	})
	err := root.Execute()

	require.ErrorContains(t, err, "network name cannot be blank")
	require.Empty(t, joins)
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	require.Empty(t, loaded.Networks)
}

func TestRegisterJoinCreatesNetworkProfileFromInviteOnCleanMachine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{
		installed:    true,
		joinRecorder: &joins,
		status: tailnet.Status{
			Self: tailnet.Peer{HostName: "macbook", IP: "100.64.0.10", Online: true},
		},
	}
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{
		"register", "macbook", "personal",
		"--control-url", "https://control.example",
		"--ssh-user", "manoj",
		"--join",
		"--enrollment-key", "tskey-auth",
	})
	require.NoError(t, root.Execute())

	require.Equal(t, []tailnet.JoinOptions{{
		ControlURL: "https://control.example",
		AuthKey:    "tskey-auth",
		Hostname:   "macbook",
	}}, joins)
	require.Contains(t, out.String(), "Joined macbook to personal")
	require.Contains(t, out.String(), "Registered macbook in personal")
	require.NotContains(t, out.String(), "tskey-auth")

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	require.Equal(t, "personal", cfg.CurrentNetwork)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
	got, err := cfg.ResolveMachine("personal", "macbook")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.10", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
}

func TestRegisterJoinDoesNotJoinWhenMachineAlreadyExists(t *testing.T) {
	path := seedConfig(t)
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{
		installed:    true,
		joinRecorder: &joins,
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"register", "homepc", "personal",
		"--control-url", "https://control.example",
		"--join",
	})
	err := root.Execute()

	require.ErrorContains(t, err, "homepc already exists")
	require.Empty(t, joins)
}

func TestRegisterForceReplacesExistingMachineProfile(t *testing.T) {
	path := seedConfig(t)
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"register", "homepc", "personal",
		"--host", "100.64.0.44",
		"--ssh-user", "lakshmi",
		"--ssh-port", "2222",
		"--workspace", "~/src/codexdock",
		"--session", "codex",
		"--agent", "codex --ask",
		"--force",
	})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := cfg.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.44", got.Host)
	require.Equal(t, "lakshmi", got.SSHUser)
	require.Equal(t, 2222, got.SSHPort)
	require.Equal(t, "~/src/codexdock", got.Workspace)
	require.Equal(t, "codex", got.SessionName)
	require.Equal(t, "codex --ask", got.AgentCommand)
}

func TestRegisterJoinForceRefreshesExistingMachineAfterJoin(t *testing.T) {
	path := seedConfig(t)
	joins := []tailnet.JoinOptions{}
	tailnetClient := fakeTailnet{
		installed:    true,
		joinRecorder: &joins,
		status: tailnet.Status{
			Self: tailnet.Peer{HostName: "homepc", IP: "100.64.0.44", Online: true},
		},
	}
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{
		"register", "homepc", "personal",
		"--control-url", "https://control.example",
		"--ssh-user", "lakshmi",
		"--join",
		"--enrollment-key", "tskey-refresh",
		"--force",
	})
	require.NoError(t, root.Execute())

	require.Equal(t, []tailnet.JoinOptions{{
		ControlURL: "https://control.example",
		AuthKey:    "tskey-refresh",
		Hostname:   "homepc",
	}}, joins)
	require.Contains(t, out.String(), "Joined homepc to personal")
	require.Contains(t, out.String(), "Registered homepc in personal")
	require.NotContains(t, out.String(), "tskey-refresh")

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := cfg.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.44", got.Host)
	require.Equal(t, "lakshmi", got.SSHUser)
	require.Equal(t, "https://control.example", cfg.Networks["personal"].ControlURL)
}

func TestInviteIssuesEnrollmentKeyAndPrintsRegisterCommand(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "https://control.example"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	issuer := &fakeControlIssuer{installed: true, invite: control.Invite{Key: "tskey-auth"}}
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"invite", "personal", "--ttl", "12h", "--reusable"})
	require.NoError(t, root.Execute())

	require.Equal(t, []control.InviteOptions{{
		Network:  "personal",
		TTL:      "12h",
		Reusable: true,
	}}, issuer.options)
	require.Contains(t, out.String(), "Enrollment key for personal")
	require.Contains(t, out.String(), "codexdock register <machine> personal --control-url https://control.example --join --enrollment-key tskey-auth")
}

func TestInviteTrimsTTLBeforeIssuingEnrollmentKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "https://control.example"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	issuer := &fakeControlIssuer{installed: true, invite: control.Invite{Key: "tskey-auth"}}
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"invite", "personal", "--ttl", "  12h  "})
	require.NoError(t, root.Execute())

	require.Equal(t, []control.InviteOptions{{
		Network: "personal",
		TTL:     "12h",
	}}, issuer.options)
}

func TestInviteRejectsBlankTTLBeforeIssuingEnrollmentKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "https://control.example"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	issuer := &fakeControlIssuer{installed: true, invite: control.Invite{Key: "tskey-auth"}}
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"invite", "personal", "--ttl", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "--ttl cannot be blank")
	require.Empty(t, issuer.options)
}

func TestInviteUsesCurrentNetworkWhenOmitted(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal", Role: "controller", ControlURL: "https://control.example"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	issuer := &fakeControlIssuer{installed: true, invite: control.Invite{Key: "tskey-auth"}}
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Control: issuer, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"invite", "--ttl", "12h"})
	require.NoError(t, root.Execute())

	require.Equal(t, []control.InviteOptions{{
		Network: "personal",
		TTL:     "12h",
	}}, issuer.options)
	require.Contains(t, out.String(), "Enrollment key for personal")
	require.Contains(t, out.String(), "codexdock register <machine> personal --control-url https://control.example --join --enrollment-key tskey-auth")
}

func TestRegisterUsesTailnetSelfIPWhenHostIsOmitted(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Self: tailnet.Peer{HostName: "macbook", IP: "100.64.0.10", Online: true},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"create", "personal"})
	require.NoError(t, root.Execute())

	root.SetArgs([]string{"register", "macbook", "personal", "--ssh-user", "manoj"})
	require.NoError(t, root.Execute())

	cfg, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := cfg.ResolveMachine("personal", "macbook")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.10", got.Host)
}

func TestRegisterTrimsMachineProfileFieldsBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"register", "macbook", "personal",
		"--host", " 100.64.0.10 ",
		"--ssh-user", " manoj ",
		"--role", " codex-host ",
		"--session", " codex ",
		"--agent", " codex --ask ",
		"--workspace", " ~/src ",
	})
	require.NoError(t, root.Execute())

	loaded, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := loaded.ResolveMachine("personal", "macbook")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.10", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
	require.Equal(t, "codex-host", got.Role)
	require.Equal(t, "codex", got.SessionName)
	require.Equal(t, "codex --ask", got.AgentCommand)
	require.Equal(t, "~/src", got.Workspace)
}

func TestRegisterRejectsNonPositiveSSHPort(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"register", "macbook", "personal", "--host", "100.64.0.10", "--ssh-user", "manoj", "--ssh-port", "0"})
	err := root.Execute()

	require.ErrorContains(t, err, "--ssh-port must be positive")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "macbook")
	require.ErrorContains(t, resolveErr, "machine macbook not found")
}

func TestRegisterRejectsInvalidSessionName(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"register", "macbook", "personal", "--host", "100.64.0.10", "--ssh-user", "manoj", "--session", "bad session"})
	err := root.Execute()

	require.ErrorContains(t, err, "invalid tmux session name")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "macbook")
	require.ErrorContains(t, resolveErr, "machine macbook not found")
}

func TestRegisterRejectsBlankAgent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"register", "macbook", "personal", "--host", "100.64.0.10", "--ssh-user", "manoj", "--agent", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "--agent cannot be empty")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "macbook")
	require.ErrorContains(t, resolveErr, "machine macbook not found")
}

func TestAdoptRegistersOnlineTailnetPeerInCurrentNetwork(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"adopt", "homepc", "--ssh-user", "manoj", "--workspace", "~/src"})
	require.NoError(t, root.Execute())

	loaded, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := loaded.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.2", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
	require.Equal(t, "~/src", got.Workspace)
	require.Contains(t, out.String(), "Adopted homepc in personal at 100.64.0.2")
	require.Contains(t, out.String(), "codexdock doctor homepc")
}

func TestAdoptTrimsMachineProfileFieldsBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"adopt", "homepc",
		"--ssh-user", " manoj ",
		"--role", " codex-host ",
		"--session", " codex ",
		"--agent", " codex --ask ",
		"--workspace", " ~/src ",
	})
	require.NoError(t, root.Execute())

	loaded, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := loaded.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.2", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
	require.Equal(t, "codex-host", got.Role)
	require.Equal(t, "codex", got.SessionName)
	require.Equal(t, "codex --ask", got.AgentCommand)
	require.Equal(t, "~/src", got.Workspace)
}

func TestAdoptRejectsBlankMachineNameBeforeSaving(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	tailnetClient := fakeTailnet{installed: true}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"adopt", "   ", "--ssh-user", "manoj"})
	err := root.Execute()

	require.ErrorContains(t, err, "machine name cannot be blank")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	require.Empty(t, loaded.Networks["personal"].Machines)
}

func TestAdoptForceRefreshesExistingTailnetPeer(t *testing.T) {
	path := seedConfigWithMachine(t, config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.99",
		SSHUser:      "old",
		SSHPort:      22,
		Role:         "old-role",
		SessionName:  "old-session",
		AgentCommand: "old-agent",
		Workspace:    "~/old",
	})
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{
		"adopt", "homepc",
		"--ssh-user", "manoj",
		"--ssh-port", "2222",
		"--workspace", "~/src",
		"--session", "codex",
		"--agent", "codex --ask",
		"--role", "codex-host",
		"--force",
	})
	require.NoError(t, root.Execute())

	loaded, err := config.NewStore(path).Load()
	require.NoError(t, err)
	got, err := loaded.ResolveMachine("personal", "homepc")
	require.NoError(t, err)
	require.Equal(t, "100.64.0.2", got.Host)
	require.Equal(t, "manoj", got.SSHUser)
	require.Equal(t, 2222, got.SSHPort)
	require.Equal(t, "~/src", got.Workspace)
	require.Equal(t, "codex", got.SessionName)
	require.Equal(t, "codex --ask", got.AgentCommand)
	require.Equal(t, "codex-host", got.Role)
}

func TestAdoptRejectsNonPositiveSSHPort(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"adopt", "homepc", "personal", "--ssh-user", "manoj", "--ssh-port", "0"})
	err := root.Execute()

	require.ErrorContains(t, err, "--ssh-port must be positive")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "homepc")
	require.ErrorContains(t, resolveErr, "machine homepc not found")
}

func TestAdoptRejectsInvalidSessionNameBeforeTailnet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{installed: false}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"adopt", "homepc", "personal", "--ssh-user", "manoj", "--session", "bad session"})
	err := root.Execute()

	require.ErrorContains(t, err, "invalid tmux session name")
	require.NotContains(t, err.Error(), "private network client not found")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "homepc")
	require.ErrorContains(t, resolveErr, "machine homepc not found")
}

func TestAdoptRejectsBlankWorkspaceBeforeTailnet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{installed: false}, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"adopt", "homepc", "personal", "--ssh-user", "manoj", "--workspace", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "--workspace cannot be empty")
	require.NotContains(t, err.Error(), "private network client not found")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "homepc")
	require.ErrorContains(t, resolveErr, "machine homepc not found")
}

func TestAdoptRefusesOfflineTailnetPeer(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: false},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"adopt", "homepc", "--ssh-user", "manoj"})
	err := root.Execute()

	require.ErrorContains(t, err, "homepc is offline")
	loaded, loadErr := config.NewStore(path).Load()
	require.NoError(t, loadErr)
	_, resolveErr := loaded.ResolveMachine("personal", "homepc")
	require.ErrorContains(t, resolveErr, "machine homepc not found")
}

func TestMachinesCommandListsRegisteredAliases(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"machines", "personal"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "homepc")
	require.Contains(t, out.String(), "codex-host")
}

func TestMachinesCommandUsesCurrentNetworkWhenOmitted(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"machines"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "homepc")
	require.Contains(t, out.String(), "codex-host")
}

func TestMachinesCommandShowsLiveTailnetStatus(t *testing.T) {
	path := seedAliasConfig(t)
	var out bytes.Buffer
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"machines", "personal"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "STATUS")
	require.Contains(t, out.String(), "homepc\t100.64.0.2\tmanoj\tcodex-host\tonline")
}

func TestMachinesCommandMatchesLiveTailnetStatusByStoredIP(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"windows-wsl": {HostName: "windows-wsl", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"machines", "personal"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "homepc\t100.64.0.2\tmanoj\tcodex-host\tonline")
}

func TestMachinesCommandShowsUnknownWhenTailnetUnavailable(t *testing.T) {
	path := seedAliasConfig(t)
	var out bytes.Buffer
	tailnetClient := fakeTailnet{installed: true, err: errors.New("status unavailable")}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"machines", "personal"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "homepc\thomepc\tmanoj\tcodex-host\tunknown")
}

func TestDevicesUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"devices"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "NAME\tHOST\tUSER\tROLE\tSTATUS")
	require.Contains(t, out.String(), "homepc\t100.64.0.2\tmanoj\tcodex-host\tunknown")
}

func TestDevicesAllShowsVisibleUnregisteredPeers(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Self: tailnet.Peer{HostName: "macbook", IP: "100.64.0.10", Online: true},
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"devices", "--all"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "macbook\t100.64.0.10\t-\tunregistered\tonline")
	require.Contains(t, out.String(), "homepc\t100.64.0.2\t-\tunregistered\tonline")
	require.Contains(t, out.String(), "codexdock adopt homepc")
}

func TestDevicesAllDoesNotShowRegisteredPeerUnderDifferentAlias(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "windows-wsl",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"devices", "--all"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "windows-wsl\t100.64.0.2\tmanoj\tcodex-host\tonline")
	require.NotContains(t, out.String(), "homepc\t100.64.0.2\t-\tunregistered")
	require.NotContains(t, out.String(), "codexdock adopt homepc")
}

func TestConnectUsesRegisteredMachineSSHMetadata(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"true"}, runner.Commands)
	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.InteractiveTargets[0])
	require.Empty(t, runner.InteractiveCommands[0])
}

func TestConnectRejectsBlankMachineNameBeforeSSH(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "   ", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "machine name cannot be blank")
	require.Empty(t, runner.Commands)
	require.Empty(t, runner.InteractiveTargets)
}

func TestConnectChecksSSHReachabilityBeforeInteractive(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"true": {err: errors.New("connection refused")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "cannot connect to homepc")
	require.ErrorContains(t, err, "codexdock machines personal")
	require.ErrorContains(t, err, "manoj@100.64.0.2")
	require.Equal(t, []string{"true"}, runner.Commands)
	require.Empty(t, runner.InteractiveTargets)
}

func TestConnectSingleMachineArgUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.InteractiveTargets[0])
	require.Empty(t, runner.InteractiveCommands[0])
}

func TestConnectSingleMachineArgInfersOnlyConfiguredNetwork(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	cfg.CurrentNetwork = ""
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:    "homepc",
		Host:    "100.64.0.2",
		SSHUser: "manoj",
		SSHPort: 22,
		Role:    "codex-host",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.InteractiveTargets[0])
	require.Empty(t, runner.InteractiveCommands[0])
}

func TestConnectSingleMachineArgRequiresCurrentNetwork(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	require.NoError(t, config.NewStore(path).Save(cfg))
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "no current network configured")
	require.Empty(t, runner.InteractiveTargets)
}

func TestConnectSingleMachineArgRequiresExplicitNetworkWhenAmbiguous(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	cfg.UpsertNetwork(config.Network{Name: "work"})
	cfg.CurrentNetwork = ""
	require.NoError(t, config.NewStore(path).Save(cfg))
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "multiple networks available (personal, work)")
	require.Empty(t, runner.InteractiveTargets)
}

func TestConnectResolvesAliasThroughTailnetWhenStoredHostIsAlias(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:    "homepc",
		Host:    "homepc",
		SSHUser: "manoj",
		SSHPort: 22,
		Role:    "codex-host",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	runner := &fakeRunner{}
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: true},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.InteractiveTargets[0])
}

func TestConnectFailsWhenTailnetPeerIsOffline(t *testing.T) {
	path := seedAliasConfig(t)
	runner := &fakeRunner{}
	tailnetClient := fakeTailnet{
		installed: true,
		status: tailnet.Status{
			Peers: map[string]tailnet.Peer{
				"homepc": {HostName: "homepc", IP: "100.64.0.2", Online: false},
			},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "homepc is offline")
	require.ErrorContains(t, err, "codexdock machines personal")
	require.Empty(t, runner.InteractiveTargets)
}

func TestConnectFailsWhenAliasCannotResolveOnPrivateNetwork(t *testing.T) {
	path := seedAliasConfig(t)
	runner := &fakeRunner{}
	tailnetClient := fakeTailnet{
		installed: true,
		status:    tailnet.Status{Peers: map[string]tailnet.Peer{}},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: tailnetClient, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"connect", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "homepc is not reachable")
	require.ErrorContains(t, err, "codexdock machines personal")
	require.Empty(t, runner.InteractiveTargets)
}

func TestRootDoesNotExposeImplementationComponentCommands(t *testing.T) {
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "config.yaml"), Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})
	names := map[string]bool{}
	for _, cmd := range root.Commands() {
		names[cmd.Name()] = true
	}

	require.False(t, names["tailscale"])
	require.False(t, names["headscale"])
}

func TestVersionCommandPrintsBuildMetadata(t *testing.T) {
	oldVersion := version.Version
	oldCommit := version.Commit
	oldDate := version.Date
	t.Cleanup(func() {
		version.Version = oldVersion
		version.Commit = oldCommit
		version.Date = oldDate
	})
	version.Version = "1.2.3"
	version.Commit = "abc123"
	version.Date = "2026-06-28T16:40:00Z"
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "config.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"version"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "codexdock 1.2.3")
	require.Contains(t, out.String(), "commit abc123")
	require.Contains(t, out.String(), "built 2026-06-28T16:40:00Z")
}

func TestDoctorReportsManagedOSSInternals(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "managed component tailscale BSD-3-Clause internal")
	require.Contains(t, out.String(), "managed component headscale BSD-3-Clause internal")
}

func TestDoctorReportsLocalSSHCommandAvailability(t *testing.T) {
	dir := t.TempDir()
	name := "ssh"
	if runtime.GOOS == "windows" {
		name = "ssh.exe"
	}
	require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"), 0o755))
	t.Setenv("PATH", dir)
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "ok ssh command found")
}

func TestDoctorRepairPlanUsesCodexDockCommandSurface(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "controller"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "CodexDock repair plan")
	require.Contains(t, out.String(), "private network client")
	require.Contains(t, out.String(), "control server")
	require.Contains(t, out.String(), "curl -fsSL https://tailscale.com/install.sh | sh")
	require.Contains(t, out.String(), "https://api.github.com/repos/juanfont/headscale/releases/latest")
	require.Contains(t, out.String(), "sudo apt install -y /tmp/headscale.deb")
	require.NotContains(t, out.String(), "open https://github.com/juanfont/headscale/releases")
}

func TestDoctorRepairPlanPreparesCodexHostWorkspace(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--workspace", "~/src/codexdock"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "CodexDock repair plan (codex-host)")
	require.Contains(t, out.String(), "sudo apt update && sudo apt install -y tmux")
	require.Contains(t, out.String(), `mkdir -p "$HOME/src/codexdock"`)
	require.NotContains(t, out.String(), "headscale")
}

func TestDoctorRepairPlanRejectsBlankWorkspaceOverride(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--workspace", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "--workspace cannot be empty")
	require.Empty(t, out.String())
}

func TestDoctorRepairPlanAcceptsSSHAuthorizedKeyForCodexHost(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})
	key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook"

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--ssh-authorized-key", key})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "ssh authorized key")
	require.Contains(t, out.String(), `grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook' "$HOME/.ssh/authorized_keys"`)
}

func TestDoctorRepairPlanReadsSSHAuthorizedKeyFileForCodexHost(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})
	key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook"
	keyPath := filepath.Join(t.TempDir(), "id_ed25519.pub")
	require.NoError(t, os.WriteFile(keyPath, []byte(key+"\n"), 0o600))

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--ssh-authorized-key-file", keyPath})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "ssh authorized key")
	require.Contains(t, out.String(), key)
}

func TestDoctorRepairPlanReadsFirstLineFromSSHAuthorizedKeyFile(t *testing.T) {
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: &out, Err: io.Discard})
	key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFirstKey macbook"
	ignored := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISecondKey old"
	keyPath := filepath.Join(t.TempDir(), "id_ed25519.pub")
	require.NoError(t, os.WriteFile(keyPath, []byte(key+"\n"+ignored+"\n"), 0o600))

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--ssh-authorized-key-file", keyPath})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), key)
	require.NotContains(t, out.String(), ignored)
}

func TestDoctorRepairPlanRejectsSSHAuthorizedKeyFileWithBlankFirstLine(t *testing.T) {
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})
	keyPath := filepath.Join(t.TempDir(), "id_ed25519.pub")
	require.NoError(t, os.WriteFile(keyPath, []byte("\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISecondLine macbook\n"), 0o600))

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--ssh-authorized-key-file", keyPath})
	err := root.Execute()

	require.ErrorContains(t, err, "SSH authorized key file "+keyPath+" first line is empty")
}

func TestDoctorRepairPlanRejectsBothSSHAuthorizedKeyForms(t *testing.T) {
	root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})
	keyPath := filepath.Join(t.TempDir(), "id_ed25519.pub")
	require.NoError(t, os.WriteFile(keyPath, []byte("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook\n"), 0o600))

	root.SetArgs([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--ssh-authorized-key", "ssh-ed25519 inline", "--ssh-authorized-key-file", keyPath})
	err := root.Execute()

	require.ErrorContains(t, err, "use either --ssh-authorized-key or --ssh-authorized-key-file")
}

func TestDoctorRepairPlanRejectsBlankSSHAuthorizedKeySources(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr string
	}{
		{
			name:    "inline",
			args:    []string{"--ssh-authorized-key", "   "},
			wantErr: "--ssh-authorized-key cannot be blank",
		},
		{
			name:    "file",
			args:    []string{"--ssh-authorized-key-file", "   "},
			wantErr: "--ssh-authorized-key-file cannot be blank",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			root := cli.New(cli.Options{ConfigPath: filepath.Join(t.TempDir(), "missing.yaml"), Tailnet: fakeTailnet{}, Out: io.Discard, Err: io.Discard})
			args := append([]string{"doctor", "--repair-plan", "--target-os", "linux", "--role", "codex-host"}, tc.args...)
			root.SetArgs(args)

			err := root.Execute()

			require.ErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestDoctorRemoteRepairPlanPrintsSSHCommandsForMachine(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "--repair-plan", "--target-os", "linux", "--role", "codex-host"})
	require.NoError(t, root.Execute())

	require.Empty(t, runner.Commands)
	require.Contains(t, out.String(), "CodexDock remote repair plan for homepc (codex-host)")
	require.Contains(t, out.String(), "ssh manoj@100.64.0.2 'sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)'")
	require.Contains(t, out.String(), "ssh manoj@100.64.0.2 'sudo apt update && sudo apt install -y tmux'")
	require.Contains(t, out.String(), `ssh manoj@100.64.0.2 'mkdir -p "$HOME/code"'`)
	require.NotContains(t, out.String(), "headscale")
}

func TestDoctorRemoteRepairPlanAcceptsSSHAuthorizedKeyForCodexHost(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})
	key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook"

	root.SetArgs([]string{"doctor", "homepc", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--ssh-authorized-key", key})
	require.NoError(t, root.Execute())

	require.Empty(t, runner.Commands)
	require.Contains(t, out.String(), `ssh manoj@100.64.0.2 'mkdir -p "$HOME/.ssh"`)
	require.Contains(t, out.String(), `grep -qxF`)
	require.Contains(t, out.String(), key)
}

func TestDoctorRemoteRepairRunsSSHCommandsWhenConfirmed(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "--repair", "--yes", "--target-os", "linux", "--role", "codex-host"})
	require.NoError(t, root.Execute())

	require.Equal(t, []ssh.Target{
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.2", User: "manoj", Port: 22},
	}, runner.Targets)
	require.Equal(t, []string{
		"curl -fsSL https://tailscale.com/install.sh | sh",
		"sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)",
		"sudo apt update && sudo apt install -y tmux",
		`mkdir -p "$HOME/code"`,
	}, runner.Commands)
	require.Contains(t, out.String(), "CodexDock remote repair plan for homepc (codex-host)")
}

func TestDoctorRemoteRepairPlanDefaultsToRegisteredWorkspace(t *testing.T) {
	path := seedConfigWithMachine(t, config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/src/codexdock",
	})
	var out bytes.Buffer
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: &fakeRunner{}, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "--repair-plan", "--target-os", "linux", "--role", "codex-host"})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), `ssh manoj@100.64.0.2 'mkdir -p "$HOME/src/codexdock"'`)
}

func TestDoctorRemoteRepairPlanRejectsBlankWorkspaceOverride(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "--repair-plan", "--target-os", "linux", "--role", "codex-host", "--workspace", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "--workspace cannot be empty")
	require.Empty(t, out.String())
	require.Empty(t, runner.Commands)
}

func TestDoctorRepairRequiresExplicitYes(t *testing.T) {
	var out bytes.Buffer
	executor := &fakeRepairExecutor{}
	root := cli.New(cli.Options{
		ConfigPath:     filepath.Join(t.TempDir(), "missing.yaml"),
		Tailnet:        fakeTailnet{},
		RepairExecutor: executor,
		Out:            &out,
		Err:            io.Discard,
	})

	root.SetArgs([]string{"doctor", "--repair", "--target-os", "linux", "--role", "client"})
	err := root.Execute()

	require.ErrorContains(t, err, "--yes")
	require.Empty(t, executor.commands)
}

func TestDoctorRepairExecutesPlanWhenConfirmed(t *testing.T) {
	executor := &fakeRepairExecutor{}
	root := cli.New(cli.Options{
		ConfigPath:     filepath.Join(t.TempDir(), "missing.yaml"),
		Tailnet:        fakeTailnet{},
		RepairExecutor: executor,
		Out:            io.Discard,
		Err:            io.Discard,
	})

	root.SetArgs([]string{"doctor", "--repair", "--yes", "--target-os", "linux", "--role", "client"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"curl -fsSL https://tailscale.com/install.sh | sh"}, executor.commands)
}

func TestDoctorChecksRemoteMachineReadiness(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
	}, runner.Commands)
	require.Contains(t, out.String(), "ok can connect to homepc")
	require.Contains(t, out.String(), "ok remote tmux found")
	require.Contains(t, out.String(), "ok remote codex found")
	require.Contains(t, out.String(), "ok workspace exists")
}

func TestDoctorSingleMachineArgUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
	}, runner.Commands)
	require.Contains(t, out.String(), "ok can connect to homepc")
}

func TestDoctorAllChecksEveryMachineInCurrentNetwork(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "workstation",
		Host:         "100.64.0.3",
		SSHUser:      "manoj",
		SSHPort:      2222,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/src",
	}))
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "--all"})
	require.NoError(t, root.Execute())

	require.Equal(t, []ssh.Target{
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.3", User: "manoj", Port: 2222},
		{Host: "100.64.0.3", User: "manoj", Port: 2222},
		{Host: "100.64.0.3", User: "manoj", Port: 2222},
		{Host: "100.64.0.3", User: "manoj", Port: 2222},
	}, runner.Targets)
	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/src",
	}, runner.Commands)
	require.Contains(t, out.String(), "ok can connect to homepc")
	require.Contains(t, out.String(), "ok can connect to workstation")
}

func TestDoctorAllContinuesAfterMachineFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "workstation",
		Host:         "100.64.0.3",
		SSHUser:      "manoj",
		SSHPort:      2222,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/src",
	}))
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"test -d $HOME/code": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"doctor", "--all"})
	err := root.Execute()

	require.ErrorContains(t, err, "doctor --all failed for 1 machine")
	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/src",
	}, runner.Commands)
	require.Contains(t, out.String(), "fail homepc: workspace ~/code not found on homepc")
	require.Contains(t, out.String(), "ok can connect to workstation")
	require.Contains(t, out.String(), "ok workspace exists")
}

func TestDoctorReturnsActionableRemoteTmuxFailure(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"command -v tmux": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "tmux not found on homepc")
	require.ErrorContains(t, err, "sudo apt update && sudo apt install -y tmux")
}

func TestDoctorReturnsActionableRemoteAgentFailure(t *testing.T) {
	path := seedConfigWithMachine(t, config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex --ask",
		Workspace:    "~/code",
	})
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"command -v codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "codex not found on homepc")
	require.ErrorContains(t, err, "ssh manoj@100.64.0.2 'command -v codex'")
	require.ErrorContains(t, err, "update the registered agent command")
}

func TestDoctorQuotesUnsafeAgentBinaryInRemoteReadinessCheck(t *testing.T) {
	path := seedConfigWithMachine(t, config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex;touch /tmp/codexdock",
		Workspace:    "~/code",
	})
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v 'codex;touch'",
		"test -d $HOME/code",
	}, runner.Commands)
}

func TestDoctorReturnsActionableRemoteWorkspaceFailure(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"test -d $HOME/code": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"doctor", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "workspace ~/code not found on homepc")
	require.ErrorContains(t, err, "ssh manoj@100.64.0.2 'mkdir -p $HOME/code'")
	require.ErrorContains(t, err, "update the registered workspace")
}

func TestCodexSendUsesTmuxSendKeysOverSSH(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "send", "homepc", "personal", "continue"})
	require.NoError(t, root.Execute())

	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Equal(t, []string{"tmux has-session -t codex", "tmux send-keys -t codex 'continue' Enter"}, runner.Commands)
}

func TestCodexSendJoinsTrailingPromptArgs(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "send", "homepc", "personal", "continue", "with", "context"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex", "tmux send-keys -t codex 'continue with context' Enter"}, runner.Commands)
}

func TestTopLevelStartUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"start", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
		"tmux has-session -t codex",
		"tmux has-session -t codex 2>/dev/null || tmux new-session -d -s codex -c \"$HOME\"/'code' 'codex'",
	}, runner.Commands)
	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Contains(t, out.String(), "Started Codex session 'codex' on homepc.")
	require.Contains(t, out.String(), "codexdock attach homepc")
}

func TestTopLevelStartReportsExistingSession(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"start", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
		"tmux has-session -t codex",
	}, runner.Commands)
	require.Contains(t, out.String(), "Codex session 'codex' already running on homepc.")
	require.Contains(t, out.String(), "codexdock attach homepc")
	require.NotContains(t, out.String(), "Started Codex session")
}

func TestTopLevelStartTrimsMachineNameInAttachGuidance(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"start", " homepc "})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "Codex session 'codex' already running on homepc.")
	require.Contains(t, out.String(), "codexdock attach homepc")
	require.NotContains(t, out.String(), "codexdock attach  homepc ")
}

func TestCodexStartReportsExistingSessionWithExplicitAttachCommand(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"codex", "start", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{
		"true",
		"command -v tmux",
		"command -v codex",
		"test -d $HOME/code",
		"tmux has-session -t codex",
	}, runner.Commands)
	require.Contains(t, out.String(), "Codex session 'codex' already running on homepc.")
	require.Contains(t, out.String(), "codexdock codex attach homepc personal")
	require.NotContains(t, out.String(), "codexdock attach homepc\n")
}

func TestCodexStartTrimsTargetNamesInAttachGuidance(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"codex", "start", " homepc ", " personal "})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "Codex session 'codex' already running on homepc.")
	require.Contains(t, out.String(), "codexdock codex attach homepc personal")
	require.NotContains(t, out.String(), "codexdock codex attach  homepc   personal ")
}

func TestCodexStartRejectsBlankNetworkNameBeforeSSH(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "start", "homepc", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "network name cannot be blank")
	require.Empty(t, runner.Commands)
}

func TestTopLevelStartFailsClearlyWhenAgentMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"command -v codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"start", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "codex not found on homepc")
	require.NotContains(t, runner.Commands, "tmux has-session -t codex 2>/dev/null || tmux new-session -d -s codex -c \"$HOME\"/'code' 'codex'")
}

func TestTopLevelStartFailsClearlyWhenWorkspaceMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"test -d $HOME/code": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"start", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "workspace ~/code not found on homepc")
	require.NotContains(t, runner.Commands, "tmux has-session -t codex 2>/dev/null || tmux new-session -d -s codex -c \"$HOME\"/'code' 'codex'")
}

func TestTopLevelAttachChecksSessionBeforeInteractiveSSH(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"attach", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex"}, runner.Commands)
	require.Equal(t, []string{"tmux attach -t codex"}, runner.InteractiveCommands)
	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.InteractiveTargets[0])
}

func TestTopLevelAttachSuggestsStartWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"attach", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "Codex session 'codex' not found on homepc")
	require.ErrorContains(t, err, "codexdock start homepc")
	require.Empty(t, runner.InteractiveCommands)
}

func TestCodexAttachSuggestsExplicitStartWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "attach", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "Codex session 'codex' not found on homepc")
	require.ErrorContains(t, err, "codexdock codex start homepc personal")
	require.Empty(t, runner.InteractiveCommands)
}

func TestTopLevelSendUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"send", "homepc", "continue"})
	require.NoError(t, root.Execute())

	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Equal(t, []string{"tmux has-session -t codex", "tmux send-keys -t codex 'continue' Enter"}, runner.Commands)
	require.Contains(t, out.String(), "Sent prompt to codex on homepc.")
}

func TestTopLevelSendJoinsTrailingPromptArgs(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"send", "homepc", "continue", "with", "context"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex", "tmux send-keys -t codex 'continue with context' Enter"}, runner.Commands)
}

func TestTopLevelSendRejectsEmptyPrompt(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"send", "homepc", "   "})
	err := root.Execute()

	require.ErrorContains(t, err, "prompt cannot be empty")
	require.Empty(t, runner.Commands)
}

func TestTopLevelSendSuggestsStartWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"send", "homepc", "continue"})
	err := root.Execute()

	require.ErrorContains(t, err, "Codex session 'codex' not found on homepc")
	require.ErrorContains(t, err, "codexdock start homepc")
	require.NotContains(t, runner.Commands, "tmux send-keys -t codex 'continue' Enter")
}

func TestCodexSendSuggestsExplicitStartWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "send", "homepc", "personal", "continue"})
	err := root.Execute()

	require.ErrorContains(t, err, "Codex session 'codex' not found on homepc")
	require.ErrorContains(t, err, "codexdock codex start homepc personal")
	require.NotContains(t, runner.Commands, "tmux send-keys -t codex 'continue' Enter")
}

func TestTopLevelSendWarnsForLongPrompt(t *testing.T) {
	path := seedConfig(t)
	var errOut bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: &errOut})
	prompt := strings.Repeat("x", 4001)

	root.SetArgs([]string{"send", "homepc", prompt})
	require.NoError(t, root.Execute())

	require.Contains(t, errOut.String(), "warning: prompt is 4001 characters")
	require.Equal(t, []string{"tmux has-session -t codex", "tmux send-keys -t codex '" + prompt + "' Enter"}, runner.Commands)
}

func TestTopLevelLogsUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{stdout: "codex simulated log\n"}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"logs", "homepc", "--lines", "20"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex", "tmux capture-pane -t codex -p -S -20"}, runner.Commands)
	require.Equal(t, "codex simulated log\n", out.String())
}

func TestTopLevelLogsRejectsNonPositiveLinesBeforeSSH(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"logs", "homepc", "--lines", "0"})
	err := root.Execute()

	require.ErrorContains(t, err, "--lines must be positive")
	require.Empty(t, runner.Commands)
}

func TestTopLevelLogsSuggestsStartWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"logs", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "Codex session 'codex' not found on homepc")
	require.ErrorContains(t, err, "codexdock start homepc")
	require.NotContains(t, runner.Commands, "tmux capture-pane -t codex -p -S -200")
}

func TestCodexLogsSuggestsExplicitStartWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "logs", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "Codex session 'codex' not found on homepc")
	require.ErrorContains(t, err, "codexdock codex start homepc personal")
	require.NotContains(t, runner.Commands, "tmux capture-pane -t codex -p -S -200")
}

func TestCodexLogsRejectsNonPositiveLinesBeforeSSH(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "logs", "homepc", "personal", "--lines", "0"})
	err := root.Execute()

	require.ErrorContains(t, err, "--lines must be positive")
	require.Empty(t, runner.Commands)
}

func TestTopLevelSessionsUsesCurrentNetwork(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{stdout: "codex: 1 windows\n"}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"sessions", "homepc"})
	require.NoError(t, root.Execute())

	require.Equal(t, "tmux ls", runner.Commands[0])
	require.Contains(t, out.String(), "homepc\tcodex\trunning")
}

func TestTopLevelSessionsWithoutMachineListsCurrentNetwork(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "workstation",
		Host:         "100.64.0.3",
		SSHUser:      "manoj",
		SSHPort:      2222,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	runner := &fakeRunner{stdout: "codex: 1 windows\n"}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"sessions"})
	require.NoError(t, root.Execute())

	require.Equal(t, []ssh.Target{
		{Host: "100.64.0.2", User: "manoj", Port: 22},
		{Host: "100.64.0.3", User: "manoj", Port: 2222},
	}, runner.Targets)
	require.Equal(t, []string{"tmux ls", "tmux ls"}, runner.Commands)
	require.Contains(t, out.String(), "DEVICE\tSESSION\tSTATUS")
	require.Contains(t, out.String(), "homepc\tcodex\trunning")
	require.Contains(t, out.String(), "workstation\tcodex\trunning")
}

func TestTopLevelSessionsWithoutMachineContinuesAfterMachineFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "workstation",
		Host:         "100.64.0.3",
		SSHUser:      "manoj",
		SSHPort:      2222,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	var out bytes.Buffer
	runner := &fakeRunner{
		targetResults: map[string]fakeRunResult{
			fakeRunKey(ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, "tmux ls"):   {err: errors.New("ssh down")},
			fakeRunKey(ssh.Target{Host: "100.64.0.3", User: "manoj", Port: 2222}, "tmux ls"): {stdout: "codex: 1 windows\n"},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"sessions"})
	err := root.Execute()

	require.ErrorContains(t, err, "sessions failed for 1 machine")
	require.Equal(t, []string{"tmux ls", "tmux ls"}, runner.Commands)
	require.Contains(t, out.String(), "DEVICE\tSESSION\tSTATUS")
	require.Contains(t, out.String(), "fail homepc: list sessions on homepc: ssh down")
	require.Contains(t, out.String(), "workstation\tcodex\trunning")
	require.NotContains(t, out.String(), "No tmux sessions found")
}

func TestTopLevelStopRequiresExplicitYes(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"stop", "homepc"})
	err := root.Execute()

	require.ErrorContains(t, err, "--yes")
	require.Empty(t, runner.Commands)
}

func TestTopLevelStopUsesCurrentNetworkWhenConfirmed(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	var errOut bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: &errOut})

	root.SetArgs([]string{"stop", "homepc", "--yes"})
	require.NoError(t, root.Execute())

	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Equal(t, []string{"tmux has-session -t codex", "tmux kill-session -t codex"}, runner.Commands)
	require.Contains(t, out.String(), "Stopped Codex session 'codex' on homepc.")
	require.Contains(t, errOut.String(), "warning: Codex session 'codex' on homepc will be killed.")
}

func TestTopLevelStopSupportsForceConfirmation(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"stop", "homepc", "--force"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex", "tmux kill-session -t codex"}, runner.Commands)
	require.Contains(t, out.String(), "Stopped Codex session 'codex' on homepc.")
}

func TestTopLevelStopReportsAlreadyStoppedWhenSessionMissing(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	var errOut bytes.Buffer
	runner := &fakeRunner{
		results: map[string]fakeRunResult{
			"tmux has-session -t codex": {err: errors.New("missing")},
		},
	}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: &errOut})

	root.SetArgs([]string{"stop", "homepc", "--yes"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex"}, runner.Commands)
	require.Contains(t, out.String(), "Codex session 'codex' is not running on homepc.")
	require.NotContains(t, out.String(), "Stopped Codex session")
	require.NotContains(t, errOut.String(), "will be killed")
}

func TestCodexStopSupportsForceConfirmation(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "stop", "homepc", "personal", "--force"})
	require.NoError(t, root.Execute())

	require.Equal(t, []string{"tmux has-session -t codex", "tmux kill-session -t codex"}, runner.Commands)
}

func TestCodexSessionsListsRemoteTmuxSessions(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{stdout: "codex: 1 windows (created Sun Jun 28 16:00:00 2026)\nresearch: 1 windows\n"}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"codex", "sessions", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Len(t, runner.Targets, 1)
	require.Len(t, runner.Commands, 1)
	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Equal(t, "tmux ls", runner.Commands[0])
	require.Contains(t, out.String(), "DEVICE\tSESSION\tSTATUS")
	require.Contains(t, out.String(), "homepc\tcodex\trunning")
	require.Contains(t, out.String(), "homepc\tresearch\trunning")
}

func TestCodexSessionsShowsStartGuidanceWhenNoSessionsExist(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"codex", "sessions", "homepc", "personal"})
	require.NoError(t, root.Execute())

	require.Len(t, runner.Commands, 1)
	require.Equal(t, "tmux ls", runner.Commands[0])
	require.Contains(t, out.String(), "No tmux sessions found on homepc.")
	require.Contains(t, out.String(), "codexdock codex start homepc personal")
}

func TestCodexSessionsTrimsTargetNamesInStartGuidance(t *testing.T) {
	path := seedConfig(t)
	var out bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: &out, Err: io.Discard})

	root.SetArgs([]string{"codex", "sessions", " homepc ", " personal "})
	require.NoError(t, root.Execute())

	require.Contains(t, out.String(), "No tmux sessions found on homepc.")
	require.Contains(t, out.String(), "codexdock codex start homepc personal")
	require.NotContains(t, out.String(), "codexdock codex start homepc  personal ")
}

func TestCodexStopRequiresExplicitYes(t *testing.T) {
	path := seedConfig(t)
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: io.Discard})

	root.SetArgs([]string{"codex", "stop", "homepc", "personal"})
	err := root.Execute()

	require.ErrorContains(t, err, "--yes")
	require.Empty(t, runner.Commands)
}

func TestCodexStopKillsSessionWhenConfirmed(t *testing.T) {
	path := seedConfig(t)
	var errOut bytes.Buffer
	runner := &fakeRunner{}
	root := cli.New(cli.Options{ConfigPath: path, Tailnet: fakeTailnet{}, Runner: runner, Out: io.Discard, Err: &errOut})

	root.SetArgs([]string{"codex", "stop", "homepc", "personal", "--yes"})
	require.NoError(t, root.Execute())

	require.Len(t, runner.Targets, 2)
	require.Len(t, runner.Commands, 2)
	require.Equal(t, ssh.Target{Host: "100.64.0.2", User: "manoj", Port: 22}, runner.Targets[0])
	require.Equal(t, []string{"tmux has-session -t codex", "tmux kill-session -t codex"}, runner.Commands)
	require.Contains(t, errOut.String(), "warning: Codex session 'codex' on homepc will be killed.")
}

func seedConfig(t *testing.T) string {
	t.Helper()
	return seedConfigWithMachine(t, config.Machine{
		Name:         "homepc",
		Host:         "100.64.0.2",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	})
}

func seedConfigWithMachine(t *testing.T, machine config.Machine) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", machine))
	require.NoError(t, config.NewStore(path).Save(cfg))
	return path
}

func seedAliasConfig(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := config.New()
	cfg.UpsertNetwork(config.Network{Name: "personal"})
	require.NoError(t, cfg.UpsertMachine("personal", config.Machine{
		Name:         "homepc",
		Host:         "homepc",
		SSHUser:      "manoj",
		SSHPort:      22,
		Role:         "codex-host",
		SessionName:  "codex",
		AgentCommand: "codex",
		Workspace:    "~/code",
	}))
	require.NoError(t, config.NewStore(path).Save(cfg))
	return path
}

type fakeRunner struct {
	Targets             []ssh.Target
	Commands            []string
	InteractiveTargets  []ssh.Target
	InteractiveCommands []string
	results             map[string]fakeRunResult
	targetResults       map[string]fakeRunResult
	stdout              string
	stderr              string
	err                 error
}

type fakeRunResult struct {
	stdout string
	stderr string
	err    error
}

type fakeTailnet struct {
	installed    bool
	status       tailnet.Status
	err          error
	joinErr      error
	joinRecorder *[]tailnet.JoinOptions
}

type fakeRepairExecutor struct {
	commands []string
}

type fakeControlIssuer struct {
	installed bool
	invite    control.Invite
	options   []control.InviteOptions
	networks  []control.NetworkOptions
	err       error
}

func (f *fakeRepairExecutor) Run(command string) error {
	f.commands = append(f.commands, command)
	return nil
}

func (f fakeControlIssuer) Installed() bool {
	return f.installed
}

func (f *fakeControlIssuer) IssueInvite(options control.InviteOptions) (control.Invite, error) {
	f.options = append(f.options, options)
	return f.invite, f.err
}

func (f *fakeControlIssuer) ProvisionNetwork(options control.NetworkOptions) error {
	f.networks = append(f.networks, options)
	return f.err
}

func (f fakeTailnet) Installed() bool {
	return f.installed
}

func (f fakeTailnet) Status() (tailnet.Status, error) {
	return f.status, f.err
}

func (f fakeTailnet) Join(options tailnet.JoinOptions) error {
	if f.joinRecorder != nil {
		*f.joinRecorder = append(*f.joinRecorder, options)
	}
	return f.joinErr
}

func (f *fakeRunner) Run(target ssh.Target, command string) (string, string, error) {
	f.Targets = append(f.Targets, target)
	f.Commands = append(f.Commands, command)
	if f.targetResults != nil {
		if result, ok := f.targetResults[fakeRunKey(target, command)]; ok {
			return result.stdout, result.stderr, result.err
		}
	}
	if f.results != nil {
		if result, ok := f.results[command]; ok {
			return result.stdout, result.stderr, result.err
		}
	}
	return f.stdout, f.stderr, f.err
}

func fakeRunKey(target ssh.Target, command string) string {
	return fmt.Sprintf("%s|%s|%d|%s", target.Host, target.User, target.Port, command)
}

func (f *fakeRunner) RunInteractive(target ssh.Target, command string) error {
	f.InteractiveTargets = append(f.InteractiveTargets, target)
	f.InteractiveCommands = append(f.InteractiveCommands, command)
	return nil
}
