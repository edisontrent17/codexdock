package component_test

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/component"
)

func TestRepairPlanForLinuxClientInstallsPrivateNetworkClient(t *testing.T) {
	plan, err := component.RepairPlan(component.Environment{OS: "linux", Distro: "ubuntu", Role: "client"})

	require.NoError(t, err)
	require.Equal(t, "client", plan.Role)
	require.Contains(t, plan.Commands(), "curl -fsSL https://tailscale.com/install.sh | sh")
	require.NotContains(t, plan.Commands(), "headscale serve")
}

func TestRepairPlanForLinuxControllerIncludesControlServerSetup(t *testing.T) {
	plan, err := component.RepairPlan(component.Environment{OS: "linux", Distro: "ubuntu", Role: "controller"})

	require.NoError(t, err)
	require.Equal(t, "controller", plan.Role)
	require.Contains(t, plan.Commands(), "curl -fsSL https://tailscale.com/install.sh | sh")
	require.Contains(t, plan.Commands(), "https://api.github.com/repos/juanfont/headscale/releases/latest")
	require.Contains(t, plan.Commands(), "headscale_${HEADSCALE_VERSION}_linux_${HEADSCALE_ARCH}.deb")
	require.Contains(t, plan.Commands(), "sudo apt install -y /tmp/headscale.deb")
	require.Contains(t, plan.Commands(), "sudo systemctl enable --now headscale")
	require.NotContains(t, plan.Commands(), "open https://github.com/juanfont/headscale/releases")
}

func TestRepairPlanForLinuxCodexHostIncludesTmuxAndWorkspace(t *testing.T) {
	plan, err := component.RepairPlan(component.Environment{OS: "linux", Distro: "ubuntu", Role: "codex-host"})

	require.NoError(t, err)
	require.Equal(t, "codex-host", plan.Role)
	require.Contains(t, plan.Commands(), "curl -fsSL https://tailscale.com/install.sh | sh")
	require.Contains(t, plan.Commands(), "sudo apt update && sudo apt install -y openssh-server")
	require.Contains(t, plan.Commands(), "sudo systemctl enable --now ssh || sudo service ssh start")
	require.Contains(t, plan.Commands(), "sudo apt update && sudo apt install -y tmux")
	require.Contains(t, plan.Commands(), `mkdir -p "$HOME/code"`)
	require.NotContains(t, plan.Commands(), "headscale")
}

func TestRepairPlanForLinuxCodexHostCanInstallAuthorizedSSHKey(t *testing.T) {
	key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook"

	plan, err := component.RepairPlan(component.Environment{
		OS:               "linux",
		Distro:           "ubuntu",
		Role:             "codex-host",
		SSHAuthorizedKey: key,
	})

	require.NoError(t, err)
	require.Contains(t, plan.Commands(), `mkdir -p "$HOME/.ssh"`)
	require.Contains(t, plan.Commands(), `grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexDockTestKey macbook' "$HOME/.ssh/authorized_keys"`)
	require.Contains(t, plan.Commands(), `chmod 600 "$HOME/.ssh/authorized_keys"`)
}

func TestRepairPlanRejectsUnsupportedOS(t *testing.T) {
	_, err := component.RepairPlan(component.Environment{OS: "plan9", Role: "client"})

	require.ErrorContains(t, err, "unsupported OS")
}
