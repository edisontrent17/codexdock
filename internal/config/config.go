package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Config struct {
	CurrentNetwork string             `yaml:"current_network,omitempty"`
	Networks       map[string]Network `yaml:"networks"`
}

type Network struct {
	Name       string             `yaml:"name"`
	Role       string             `yaml:"role,omitempty"`
	ControlURL string             `yaml:"control_url,omitempty"`
	Machines   map[string]Machine `yaml:"machines,omitempty"`
}

type Machine struct {
	Name         string `yaml:"name"`
	Host         string `yaml:"host,omitempty"`
	SSHUser      string `yaml:"ssh_user,omitempty"`
	SSHPort      int    `yaml:"ssh_port,omitempty"`
	Role         string `yaml:"role,omitempty"`
	SessionName  string `yaml:"session_name,omitempty"`
	AgentCommand string `yaml:"agent_command,omitempty"`
	Workspace    string `yaml:"workspace,omitempty"`
}

type Store struct {
	path string
}

func New() Config {
	return Config{Networks: map[string]Network{}}
}

func DefaultPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".codexdock", "config.yaml"), nil
}

func NewStore(path string) Store {
	return Store{path: path}
}

func (s Store) Load() (Config, error) {
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return New(), nil
	}
	if err != nil {
		return Config{}, err
	}

	cfg := New()
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	if cfg.Networks == nil {
		cfg.Networks = map[string]Network{}
	}
	for name, network := range cfg.Networks {
		if network.Name == "" {
			network.Name = name
		}
		if network.Machines == nil {
			network.Machines = map[string]Machine{}
		}
		cfg.Networks[name] = network
	}
	return cfg, nil
}

func (s Store) Save(cfg Config) error {
	if cfg.Networks == nil {
		cfg.Networks = map[string]Network{}
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0o600)
}

func (c *Config) UpsertNetwork(network Network) {
	if c.Networks == nil {
		c.Networks = map[string]Network{}
	}
	if network.Name == "" {
		return
	}
	existing := c.Networks[network.Name]
	if network.Machines == nil {
		network.Machines = existing.Machines
	}
	if network.Role == "" {
		network.Role = existing.Role
	}
	if network.ControlURL == "" {
		network.ControlURL = existing.ControlURL
	}
	if network.Machines == nil {
		network.Machines = map[string]Machine{}
	}
	c.Networks[network.Name] = network
	if c.CurrentNetwork == "" {
		c.CurrentNetwork = network.Name
	}
}

func (c *Config) UpsertMachine(networkName string, machine Machine) error {
	if c.Networks == nil {
		c.Networks = map[string]Network{}
	}
	if machine.Name == "" {
		return errors.New("machine name is required")
	}
	network, ok := c.Networks[networkName]
	if !ok {
		return fmt.Errorf("network %s not found", networkName)
	}
	if network.Machines == nil {
		network.Machines = map[string]Machine{}
	}
	if _, exists := network.Machines[machine.Name]; exists {
		return fmt.Errorf("machine %s already exists in network %s", machine.Name, networkName)
	}
	if machine.Host == "" {
		machine.Host = machine.Name
	}
	if machine.SSHPort == 0 {
		machine.SSHPort = 22
	}
	if machine.SessionName == "" {
		machine.SessionName = "codex"
	}
	if machine.AgentCommand == "" {
		machine.AgentCommand = "codex"
	}
	if machine.Workspace == "" {
		machine.Workspace = "~/code"
	}
	network.Machines[machine.Name] = machine
	c.Networks[networkName] = network
	return nil
}

func (c *Config) SetNetworkControlURL(networkName, controlURL string) error {
	network, ok := c.Networks[networkName]
	if !ok {
		return fmt.Errorf("network %s not found", networkName)
	}
	network.ControlURL = controlURL
	c.Networks[networkName] = network
	return nil
}

func (c Config) ResolveMachine(networkName, machineName string) (Machine, error) {
	network, ok := c.Networks[networkName]
	if !ok {
		return Machine{}, fmt.Errorf("network %s not found", networkName)
	}
	machine, ok := network.Machines[machineName]
	if !ok {
		return Machine{}, fmt.Errorf("machine %s not found in network %s", machineName, networkName)
	}
	if machine.Host == "" {
		machine.Host = machine.Name
	}
	if machine.SSHPort == 0 {
		machine.SSHPort = 22
	}
	return machine, nil
}
