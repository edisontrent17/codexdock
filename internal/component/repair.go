package component

import (
	"fmt"
	"strings"
)

type Environment struct {
	OS               string
	Distro           string
	Role             string
	Workspace        string
	SSHAuthorizedKey string
}

type Plan struct {
	Role  string
	Steps []Step
}

type Step struct {
	Name        string
	Description string
	Command     string
}

func RepairPlan(env Environment) (Plan, error) {
	if env.Role == "" {
		env.Role = "client"
	}
	plan := Plan{Role: env.Role}

	clientSteps, err := privateNetworkClientSteps(env)
	if err != nil {
		return Plan{}, err
	}
	plan.Steps = append(plan.Steps, clientSteps...)

	switch env.Role {
	case "client":
		return plan, nil
	case "controller":
		controlSteps, err := controlServerSteps(env)
		if err != nil {
			return Plan{}, err
		}
		plan.Steps = append(plan.Steps, controlSteps...)
		return plan, nil
	case "codex-host":
		codexSteps, err := codexHostSteps(env)
		if err != nil {
			return Plan{}, err
		}
		plan.Steps = append(plan.Steps, codexSteps...)
		return plan, nil
	default:
		return Plan{}, fmt.Errorf("unsupported role %q", env.Role)
	}
}

func (p Plan) Commands() string {
	commands := make([]string, 0, len(p.Steps))
	for _, step := range p.Steps {
		if step.Command != "" {
			commands = append(commands, step.Command)
		}
	}
	return strings.Join(commands, "\n")
}

func privateNetworkClientSteps(env Environment) ([]Step, error) {
	switch env.OS {
	case "linux":
		return []Step{{
			Name:        "private network client",
			Description: "Install the managed private network client.",
			Command:     "curl -fsSL https://tailscale.com/install.sh | sh",
		}}, nil
	case "darwin":
		return []Step{{
			Name:        "private network client",
			Description: "Install the managed private network client for macOS.",
			Command:     "brew install --cask tailscale",
		}}, nil
	default:
		return nil, fmt.Errorf("unsupported OS %q", env.OS)
	}
}

func controlServerSteps(env Environment) ([]Step, error) {
	if env.OS != "linux" {
		return nil, fmt.Errorf("control server setup requires linux, got %q", env.OS)
	}
	return []Step{
		{
			Name:        "control server package",
			Description: "Download the latest managed control server release package for this Linux architecture.",
			Command:     `HEADSCALE_VERSION=$(curl -fsSL https://api.github.com/repos/juanfont/headscale/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n 1); test -n "$HEADSCALE_VERSION"; HEADSCALE_ARCH=$(dpkg --print-architecture); curl -fsSL -o /tmp/headscale.deb "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_${HEADSCALE_ARCH}.deb"`,
		},
		{
			Name:        "control server install",
			Description: "Install the managed control server package.",
			Command:     "sudo apt install -y /tmp/headscale.deb",
		},
		{
			Name:        "control server service",
			Description: "Enable the managed control server service after package installation.",
			Command:     "sudo systemctl enable --now headscale",
		},
	}, nil
}

func codexHostSteps(env Environment) ([]Step, error) {
	steps := []Step{}
	switch env.OS {
	case "linux":
		steps = append(steps, Step{
			Name:        "ssh server",
			Description: "Install and start OpenSSH so other machines can reach this Codex host.",
			Command:     "sudo apt update && sudo apt install -y openssh-server && (sudo systemctl enable --now ssh || sudo service ssh start)",
		})
		if strings.TrimSpace(env.SSHAuthorizedKey) != "" {
			steps = append(steps, Step{
				Name:        "ssh authorized key",
				Description: "Install the provided public key for passwordless SSH from the controlling machine.",
				Command:     authorizedKeyCommand(env.SSHAuthorizedKey),
			})
		}
		steps = append(steps, Step{
			Name:        "tmux",
			Description: "Install tmux for long-running Codex sessions.",
			Command:     "sudo apt update && sudo apt install -y tmux",
		})
	default:
		return nil, fmt.Errorf("codex host setup requires linux, got %q", env.OS)
	}
	steps = append(steps, Step{
		Name:        "codex workspace",
		Description: "Create the default workspace used when CodexDock starts remote sessions.",
		Command:     "mkdir -p " + shellWorkspacePath(env.Workspace),
	})
	steps = append(steps, Step{
		Name:        "codex agent",
		Description: "Install and authenticate the Codex CLI for this user before starting sessions.",
	})
	return steps, nil
}

func authorizedKeyCommand(key string) string {
	key = strings.TrimSpace(key)
	quotedKey := shellQuote(key)
	return `mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" && touch "$HOME/.ssh/authorized_keys" && (grep -qxF ` + quotedKey + ` "$HOME/.ssh/authorized_keys" || printf '%s\n' ` + quotedKey + ` >> "$HOME/.ssh/authorized_keys") && chmod 600 "$HOME/.ssh/authorized_keys"`
}

func shellWorkspacePath(workspace string) string {
	workspace = strings.TrimSpace(workspace)
	if workspace == "" {
		workspace = "~/code"
	}
	if workspace == "~" {
		return `"$HOME"`
	}
	if rest, ok := strings.CutPrefix(workspace, "~/"); ok {
		return `"$HOME/` + escapeDoubleQuoted(rest) + `"`
	}
	return shellQuote(workspace)
}

func escapeDoubleQuoted(value string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "`", "\\`", `$`, `\$`)
	return replacer.Replace(value)
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", `'\''`) + "'"
}
