package cli

import (
	"fmt"
	"io"
	"net"
	"os"
	"os/user"
	"runtime"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/spf13/cobra"
	"github.com/trentsoftware/codexdock/internal/component"
	"github.com/trentsoftware/codexdock/internal/config"
	"github.com/trentsoftware/codexdock/internal/control"
	"github.com/trentsoftware/codexdock/internal/ssh"
	"github.com/trentsoftware/codexdock/internal/tailnet"
	"github.com/trentsoftware/codexdock/internal/tmux"
	"github.com/trentsoftware/codexdock/internal/version"
)

type Options struct {
	ConfigPath     string
	Runner         ssh.Runner
	Tailnet        tailnet.Client
	Control        control.Issuer
	RepairExecutor component.Executor
	Out            io.Writer
	Err            io.Writer
}

const longPromptWarningThreshold = 4000

func New(options Options) *cobra.Command {
	if options.Out == nil {
		options.Out = os.Stdout
	}
	if options.Err == nil {
		options.Err = os.Stderr
	}
	if options.ConfigPath == "" {
		path, err := config.DefaultPath()
		if err == nil {
			options.ConfigPath = path
		}
	}
	if options.Runner == nil {
		options.Runner = ssh.SystemRunner{Stdin: os.Stdin, Stdout: options.Out, Stderr: options.Err}
	}
	if options.Tailnet == nil {
		options.Tailnet = tailnet.SystemClient{}
	}
	if options.Control == nil {
		options.Control = control.SystemIssuer{}
	}

	root := &cobra.Command{
		Use:           "codexdock",
		Short:         "Private machine registration and Codex session control",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.SetOut(options.Out)
	root.SetErr(options.Err)

	root.AddCommand(initCommand(options))
	root.AddCommand(createCommand(options))
	root.AddCommand(inviteCommand(options))
	root.AddCommand(registerCommand(options))
	root.AddCommand(adoptCommand(options))
	root.AddCommand(devicesCommand(options))
	root.AddCommand(machinesCommand(options))
	root.AddCommand(connectCommand(options))
	root.AddCommand(doctorCommand(options))
	root.AddCommand(codexCommand(options))
	root.AddCommand(topLevelSessionsCommand(options))
	root.AddCommand(topLevelStartCommand(options))
	root.AddCommand(topLevelAttachCommand(options))
	root.AddCommand(topLevelSendCommand(options))
	root.AddCommand(topLevelLogsCommand(options))
	root.AddCommand(topLevelStopCommand(options))
	root.AddCommand(versionCommand())
	return root
}

func inviteCommand(options Options) *cobra.Command {
	var ttl string
	var reusable bool
	var ephemeral bool
	cmd := &cobra.Command{
		Use:   "invite [network]",
		Short: "Issue a CodexDock enrollment key for a network",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			normalizedTTL, err := normalizeInviteTTL(ttl, cmd.Flags().Changed("ttl"))
			if err != nil {
				return err
			}
			networkName, err := networkFromArgsOrCurrent(options, args)
			if err != nil {
				return err
			}
			cfg, err := config.NewStore(options.ConfigPath).Load()
			if err != nil {
				return err
			}
			network, ok := cfg.Networks[networkName]
			if !ok {
				return fmt.Errorf("network %s not found", networkName)
			}
			if network.ControlURL == "" {
				return fmt.Errorf("control URL is required to invite machines to %s; run codexdock create %s --control-url <url> --force", networkName, networkName)
			}
			if !options.Control.Installed() {
				return fmt.Errorf("control server client not found; run codexdock doctor --repair-plan --role controller")
			}
			invite, err := options.Control.IssueInvite(control.InviteOptions{
				Network:   networkName,
				TTL:       normalizedTTL,
				Reusable:  reusable,
				Ephemeral: ephemeral,
			})
			if err != nil {
				return err
			}
			if invite.Key == "" {
				return fmt.Errorf("control server returned an empty enrollment key")
			}
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Enrollment key for %s:\n  %s\n", networkName, invite.Key)
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Register another machine:\n  codexdock register <machine> %s --control-url %s --join --enrollment-key %s\n", networkName, network.ControlURL, invite.Key)
			return nil
		},
	}
	cmd.Flags().StringVar(&ttl, "ttl", "24h", "enrollment key lifetime")
	cmd.Flags().BoolVar(&reusable, "reusable", false, "allow the enrollment key to be reused")
	cmd.Flags().BoolVar(&ephemeral, "ephemeral", false, "mark joined machines as ephemeral")
	return cmd
}

func normalizeInviteTTL(value string, provided bool) (string, error) {
	trimmed := strings.TrimSpace(value)
	if provided && trimmed == "" {
		return "", fmt.Errorf("--ttl cannot be blank")
	}
	if trimmed == "" {
		return "24h", nil
	}
	return trimmed, nil
}

func versionCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print CodexDock build metadata",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			_, _ = fmt.Fprint(cmd.OutOrStdout(), version.String())
			return nil
		},
	}
}

func initCommand(options Options) *cobra.Command {
	var network config.Network
	var machine config.Machine
	var deviceName string
	var force bool
	cmd := &cobra.Command{
		Use:   "init",
		Short: "Create a network profile and register the first machine",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			machineProvided := cmd.Flags().Changed("machine")
			deviceProvided := cmd.Flags().Changed("device")
			if machineProvided && deviceProvided {
				return fmt.Errorf("use either --machine or --device, not both")
			}
			if cmd.Flags().Changed("network") {
				name, err := normalizeRequiredName("--network", network.Name)
				if err != nil {
					return err
				}
				network.Name = name
			}
			if network.Name == "" {
				network.Name = "personal"
			}
			if machineProvided {
				name, err := normalizeRequiredName("--machine", machine.Name)
				if err != nil {
					return err
				}
				machine.Name = name
			}
			if deviceProvided {
				name, err := normalizeRequiredName("--device", deviceName)
				if err != nil {
					return err
				}
				machine.Name = name
			}
			if machine.Name == "" {
				return fmt.Errorf("--machine or --device is required")
			}
			if network.Role == "" {
				network.Role = "client"
			}
			if err := validateNetworkRole("--network-role", network.Role); err != nil {
				return err
			}
			controlURL, err := normalizeOptionalControlURL("--control-url", network.ControlURL, cmd.Flags().Changed("control-url"))
			if err != nil {
				return err
			}
			network.ControlURL = controlURL
			machine = normalizeMachineProfile(machine)
			if machine.SSHUser == "" {
				machine.SSHUser = currentUsername()
			}
			if machine.Host == "" {
				machine.Host = machine.Name
			}
			if err := validateMachineProfile(machine); err != nil {
				return err
			}

			store := config.NewStore(options.ConfigPath)
			cfg, err := store.Load()
			if err != nil {
				return err
			}
			cfg.UpsertNetwork(network)
			if err := putMachine(&cfg, network.Name, machine, force); err != nil {
				return err
			}
			if err := store.Save(cfg); err != nil {
				return err
			}
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Initialized %s in %s\n", machine.Name, network.Name)
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Next:\n  codexdock doctor %s %s\n", machine.Name, network.Name)
			return nil
		},
	}
	cmd.Flags().StringVar(&network.Name, "network", "", "CodexDock network name")
	cmd.Flags().StringVar(&network.Role, "network-role", "client", "network role for this machine: client or controller")
	cmd.Flags().StringVar(&network.ControlURL, "control-url", "", "CodexDock control URL for this network")
	cmd.Flags().StringVar(&machine.Name, "machine", "", "machine alias")
	cmd.Flags().StringVar(&deviceName, "device", "", "device alias (same as --machine)")
	cmd.Flags().StringVar(&machine.Host, "host", "", "host or tailnet IP for SSH")
	cmd.Flags().StringVar(&machine.SSHUser, "ssh-user", "", "SSH user")
	cmd.Flags().IntVar(&machine.SSHPort, "ssh-port", 22, "SSH port")
	cmd.Flags().StringVar(&machine.Role, "role", "developer", "machine role")
	cmd.Flags().StringVar(&machine.SessionName, "session", "codex", "default tmux session")
	cmd.Flags().StringVar(&machine.AgentCommand, "agent", "codex", "default agent command")
	cmd.Flags().StringVar(&machine.Workspace, "workspace", "~/code", "default workspace")
	cmd.Flags().BoolVar(&force, "force", false, "replace an existing machine profile")
	return cmd
}

func createCommand(options Options) *cobra.Command {
	var role string
	var controlURL string
	var force bool
	var provision bool
	cmd := &cobra.Command{
		Use:   "create <network>",
		Short: "Create a CodexDock network profile",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			networkName, err := normalizeRequiredName("network name", args[0])
			if err != nil {
				return err
			}
			if err := validateNetworkRole("--role", role); err != nil {
				return err
			}
			normalizedControlURL, err := normalizeOptionalControlURL("--control-url", controlURL, cmd.Flags().Changed("control-url"))
			if err != nil {
				return err
			}
			store := config.NewStore(options.ConfigPath)
			cfg, err := store.Load()
			if err != nil {
				return err
			}
			if _, exists := cfg.Networks[networkName]; exists && !force {
				return fmt.Errorf("network %s already exists; use --force to update it", networkName)
			}
			if provision {
				if !options.Control.Installed() {
					return fmt.Errorf("control server client not found; run codexdock doctor --repair-plan --role controller")
				}
				if err := options.Control.ProvisionNetwork(control.NetworkOptions{Name: networkName}); err != nil {
					return fmt.Errorf("provision network %s: %w", networkName, err)
				}
			}
			cfg.UpsertNetwork(config.Network{Name: networkName, Role: role, ControlURL: normalizedControlURL})
			if err := store.Save(cfg); err != nil {
				return err
			}
			if provision {
				_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Provisioned network %s\n", networkName)
			}
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Created network %s\n", networkName)
			printJoinGuidance(cmd.OutOrStdout(), config.Network{Name: networkName, ControlURL: normalizedControlURL})
			return nil
		},
	}
	cmd.Flags().StringVar(&role, "role", "client", "network role for this machine: client or controller")
	cmd.Flags().StringVar(&controlURL, "control-url", "", "CodexDock control URL for joining this network")
	cmd.Flags().BoolVar(&force, "force", false, "update an existing network profile")
	cmd.Flags().BoolVar(&provision, "provision", false, "provision the network on the configured controller")
	return cmd
}

func registerCommand(options Options) *cobra.Command {
	var machine config.Machine
	var controlURL string
	var join bool
	var enrollmentKey string
	var force bool
	cmd := &cobra.Command{
		Use:   "register <machine> [network]",
		Short: "Register this machine with a friendly alias",
		Args:  cobra.RangeArgs(1, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			enrollmentKeyProvided := cmd.Flags().Changed("enrollment-key")
			if enrollmentKeyProvided && !join {
				return fmt.Errorf("--enrollment-key requires --join")
			}
			if enrollmentKeyProvided && strings.TrimSpace(enrollmentKey) == "" {
				return fmt.Errorf("--enrollment-key cannot be blank")
			}
			normalizedControlURL, err := normalizeOptionalControlURL("--control-url", controlURL, cmd.Flags().Changed("control-url"))
			if err != nil {
				return err
			}
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := networkFromArgsOrCurrent(options, args[1:])
			if err != nil {
				return err
			}
			machine = normalizeMachineProfile(machine)
			if err := validateMachineProfile(machine); err != nil {
				return err
			}
			store := config.NewStore(options.ConfigPath)
			cfg, err := store.Load()
			if err != nil {
				return err
			}
			machine.Name = machineName
			if machine.SSHUser == "" {
				machine.SSHUser = currentUsername()
			}
			network, ok := cfg.Networks[networkName]
			if !ok {
				if !join || normalizedControlURL == "" {
					return fmt.Errorf("network %s not found", networkName)
				}
				cfg.UpsertNetwork(config.Network{Name: networkName, Role: "client", ControlURL: normalizedControlURL})
				network = cfg.Networks[networkName]
			}
			if _, exists := network.Machines[machine.Name]; exists && !force {
				return fmt.Errorf("machine %s already exists in network %s; use --force to replace it", machine.Name, networkName)
			}
			if normalizedControlURL != "" {
				if err := cfg.SetNetworkControlURL(networkName, normalizedControlURL); err != nil {
					return err
				}
				network = cfg.Networks[networkName]
			}
			if join {
				joinURL, err := requiredJoinControlURL(networkName, network.ControlURL)
				if err != nil {
					return err
				}
				if !options.Tailnet.Installed() {
					return fmt.Errorf("private network client not found; run codexdock doctor --repair-plan")
				}
				if err := options.Tailnet.Join(tailnet.JoinOptions{ControlURL: joinURL, AuthKey: enrollmentKey, Hostname: machine.Name}); err != nil {
					return fmt.Errorf("join network %s: %w", networkName, err)
				}
				_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Joined %s to %s\n", machine.Name, networkName)
			}
			if machine.Host == "" {
				machine.Host = discoverSelfHost(options.Tailnet, machine.Name)
			}
			if err := putMachine(&cfg, networkName, machine, force); err != nil {
				return err
			}
			if err := store.Save(cfg); err != nil {
				return err
			}
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Registered %s in %s\n", machineName, networkName)
			return nil
		},
	}
	cmd.Flags().StringVar(&machine.Host, "host", "", "host or tailnet IP for SSH")
	cmd.Flags().StringVar(&machine.SSHUser, "ssh-user", "", "SSH user")
	cmd.Flags().IntVar(&machine.SSHPort, "ssh-port", 22, "SSH port")
	cmd.Flags().StringVar(&machine.Role, "role", "developer", "machine role")
	cmd.Flags().StringVar(&machine.SessionName, "session", "codex", "default tmux session")
	cmd.Flags().StringVar(&machine.AgentCommand, "agent", "codex", "default agent command")
	cmd.Flags().StringVar(&machine.Workspace, "workspace", "~/code", "default workspace")
	cmd.Flags().StringVar(&controlURL, "control-url", "", "CodexDock control URL for this network")
	cmd.Flags().BoolVar(&join, "join", false, "join the CodexDock private network while registering")
	cmd.Flags().StringVar(&enrollmentKey, "enrollment-key", "", "optional enrollment key for non-interactive joining")
	cmd.Flags().BoolVar(&force, "force", false, "replace an existing machine profile")
	return cmd
}

func adoptCommand(options Options) *cobra.Command {
	var machine config.Machine
	var force bool
	cmd := &cobra.Command{
		Use:   "adopt <machine> [network]",
		Short: "Adopt a visible private-network peer into CodexDock",
		Args:  cobra.RangeArgs(1, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := networkFromArgsOrCurrent(options, args[1:])
			if err != nil {
				return err
			}
			machine = normalizeMachineProfile(machine)
			if err := validateMachineProfile(machine); err != nil {
				return err
			}
			if !options.Tailnet.Installed() {
				return fmt.Errorf("private network client not found; run codexdock doctor --repair-plan")
			}
			status, err := options.Tailnet.Status()
			if err != nil {
				return fmt.Errorf("private network status unavailable; run codexdock doctor")
			}
			peer, ok := status.Resolve(machineName)
			if !ok || peer.IP == "" {
				return fmt.Errorf("%s is not reachable on private network; run codexdock devices %s", machineName, networkName)
			}
			if !peer.Online {
				return fmt.Errorf("%s is offline on private network; run codexdock devices %s", machineName, networkName)
			}

			machine.Name = machineName
			machine.Host = peer.IP
			if machine.SSHUser == "" {
				machine.SSHUser = currentUsername()
			}
			store := config.NewStore(options.ConfigPath)
			cfg, err := store.Load()
			if err != nil {
				return err
			}
			if err := putMachine(&cfg, networkName, machine, force); err != nil {
				return err
			}
			if err := store.Save(cfg); err != nil {
				return err
			}
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Adopted %s in %s at %s\n", machine.Name, networkName, machine.Host)
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Next:\n  codexdock doctor %s\n", machine.Name)
			return nil
		},
	}
	cmd.Flags().StringVar(&machine.SSHUser, "ssh-user", "", "SSH user")
	cmd.Flags().IntVar(&machine.SSHPort, "ssh-port", 22, "SSH port")
	cmd.Flags().StringVar(&machine.Role, "role", "developer", "machine role")
	cmd.Flags().StringVar(&machine.SessionName, "session", "codex", "default tmux session")
	cmd.Flags().StringVar(&machine.AgentCommand, "agent", "codex", "default agent command")
	cmd.Flags().StringVar(&machine.Workspace, "workspace", "~/code", "default workspace")
	cmd.Flags().BoolVar(&force, "force", false, "replace an existing machine profile")
	return cmd
}

func putMachine(cfg *config.Config, networkName string, machine config.Machine, force bool) error {
	machine = normalizeMachineProfile(machine)
	network, ok := cfg.Networks[networkName]
	if !ok {
		return fmt.Errorf("network %s not found", networkName)
	}
	if !force {
		if _, exists := network.Machines[machine.Name]; exists {
			return fmt.Errorf("machine %s already exists in network %s; use --force to replace it", machine.Name, networkName)
		}
		return cfg.UpsertMachine(networkName, machine)
	}
	if network.Machines == nil {
		network.Machines = map[string]config.Machine{}
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
	cfg.Networks[networkName] = network
	return nil
}

func validateSSHPort(port int) error {
	if port <= 0 {
		return fmt.Errorf("--ssh-port must be positive")
	}
	return nil
}

func validateMachineProfile(machine config.Machine) error {
	machine = normalizeMachineProfile(machine)
	if err := validateSSHPort(machine.SSHPort); err != nil {
		return err
	}
	if err := tmux.ValidateSessionName(machine.SessionName); err != nil {
		return err
	}
	if strings.TrimSpace(machine.AgentCommand) == "" {
		return fmt.Errorf("--agent cannot be empty")
	}
	if strings.TrimSpace(machine.Workspace) == "" {
		return fmt.Errorf("--workspace cannot be empty")
	}
	return nil
}

func normalizeMachineProfile(machine config.Machine) config.Machine {
	machine.Name = strings.TrimSpace(machine.Name)
	machine.Host = strings.TrimSpace(machine.Host)
	machine.SSHUser = strings.TrimSpace(machine.SSHUser)
	machine.Role = strings.TrimSpace(machine.Role)
	machine.SessionName = strings.TrimSpace(machine.SessionName)
	machine.AgentCommand = strings.TrimSpace(machine.AgentCommand)
	machine.Workspace = strings.TrimSpace(machine.Workspace)
	return machine
}

func normalizeRequiredName(label, value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", fmt.Errorf("%s cannot be blank", label)
	}
	return trimmed, nil
}

func validateNetworkRole(flag, role string) error {
	switch role {
	case "client", "controller":
		return nil
	default:
		return fmt.Errorf("%s must be client or controller", flag)
	}
}

func normalizeOptionalControlURL(flag, value string, provided bool) (string, error) {
	if !provided && value == "" {
		return "", nil
	}
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", fmt.Errorf("%s cannot be blank", flag)
	}
	return trimmed, nil
}

func requiredJoinControlURL(networkName, value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", fmt.Errorf("control URL is required to join network %s; pass --control-url or run codexdock create %s --control-url <url> --force", networkName, networkName)
	}
	return trimmed, nil
}

func devicesCommand(options Options) *cobra.Command {
	var all bool
	cmd := &cobra.Command{
		Use:   "devices [network]",
		Short: "List devices in the current CodexDock network",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			networkName, err := networkFromArgsOrCurrent(options, args)
			if err != nil {
				return err
			}
			return printMachines(options, cmd.OutOrStdout(), networkName, all)
		},
	}
	cmd.Flags().BoolVar(&all, "all", false, "include visible private-network peers that are not registered")
	return cmd
}

func machinesCommand(options Options) *cobra.Command {
	var all bool
	cmd := &cobra.Command{
		Use:   "machines [network]",
		Short: "List registered machines",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			networkName, err := networkFromArgsOrCurrent(options, args)
			if err != nil {
				return err
			}
			return printMachines(options, cmd.OutOrStdout(), networkName, all)
		},
	}
	cmd.Flags().BoolVar(&all, "all", false, "include visible private-network peers that are not registered")
	return cmd
}

func printMachines(options Options, out io.Writer, networkName string, all bool) error {
	cfg, err := config.NewStore(options.ConfigPath).Load()
	if err != nil {
		return err
	}
	network, ok := cfg.Networks[networkName]
	if !ok {
		return fmt.Errorf("network %s not found", networkName)
	}
	names := make([]string, 0, len(network.Machines))
	for name := range network.Machines {
		names = append(names, name)
	}
	sort.Strings(names)
	status, live := tailnetStatus(options.Tailnet)
	_, _ = fmt.Fprintln(out, "NAME\tHOST\tUSER\tROLE\tSTATUS")
	registered := map[string]bool{}
	for _, name := range names {
		machine := network.Machines[name]
		registered[machine.Name] = true
		host, state := machineDisplayStatus(status, live, machine)
		_, _ = fmt.Fprintf(out, "%s\t%s\t%s\t%s\t%s\n", machine.Name, host, machine.SSHUser, machine.Role, state)
	}
	if all && live {
		unregistered := visibleUnregisteredPeers(status, registered)
		for _, peer := range unregistered {
			state := "offline"
			if peer.Online {
				state = "online"
			}
			_, _ = fmt.Fprintf(out, "%s\t%s\t-\tunregistered\t%s\n", visiblePeerName(peer), peer.IP, state)
		}
		if len(unregistered) > 0 {
			_, _ = fmt.Fprintln(out, "Adopt a visible peer:")
			_, _ = fmt.Fprintf(out, "  codexdock adopt %s\n", visiblePeerName(unregistered[0]))
		}
	}
	return nil
}

func visibleUnregisteredPeers(status tailnet.Status, registered map[string]bool) []tailnet.Peer {
	byName := map[string]tailnet.Peer{}
	add := func(peer tailnet.Peer) {
		name := visiblePeerName(peer)
		if name == "" || peer.IP == "" || registered[name] {
			return
		}
		byName[name] = peer
	}
	add(status.Self)
	for _, peer := range status.Peers {
		add(peer)
	}

	names := make([]string, 0, len(byName))
	for name := range byName {
		names = append(names, name)
	}
	sort.Strings(names)
	peers := make([]tailnet.Peer, 0, len(names))
	for _, name := range names {
		peers = append(peers, byName[name])
	}
	return peers
}

func visiblePeerName(peer tailnet.Peer) string {
	if peer.HostName != "" {
		return peer.HostName
	}
	if peer.DNSName != "" {
		return strings.Split(peer.DNSName, ".")[0]
	}
	return ""
}

func connectCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "connect <machine> [network]",
		Short: "SSH into a registered machine",
		Args:  cobra.RangeArgs(1, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := networkFromArgsOrCurrent(options, args[1:])
			if err != nil {
				return err
			}
			machine, err := resolve(options, networkName, machineName)
			if err != nil {
				return err
			}
			target := targetFor(machine)
			if err := runRemoteCheck(options.Runner, target, "true"); err != nil {
				return fmt.Errorf("cannot connect to %s; run codexdock machines %s or verify SSH to %s", machine.Name, networkName, sshTargetSpec(target))
			}
			return options.Runner.RunInteractive(target, "")
		},
	}
}

func doctorCommand(options Options) *cobra.Command {
	var repairPlan bool
	var repair bool
	var yes bool
	var all bool
	var targetOS string
	var role string
	var workspace string
	var sshAuthorizedKey string
	var sshAuthorizedKeyFile string
	cmd := &cobra.Command{
		Use:   "doctor",
		Short: "Check local CodexDock readiness",
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) == 0 || len(args) == 1 || len(args) == 2 {
				return nil
			}
			return fmt.Errorf("doctor expects no args, <machine>, or <machine> <network>")
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			if all {
				if len(args) > 0 {
					return fmt.Errorf("--all cannot be used with a machine argument")
				}
				if repair || repairPlan {
					return fmt.Errorf("--all cannot be used with repair commands")
				}
				networkName, err := currentNetworkName(options)
				if err != nil {
					return err
				}
				return runRemoteDoctorForNetwork(options, cmd.OutOrStdout(), networkName)
			}
			if len(args) > 0 && (repair || repairPlan) {
				if repair && !yes {
					return fmt.Errorf("refusing to run remote repair without --yes; inspect steps first with --repair-plan")
				}
				if err := validateRepairWorkspace(workspace, cmd.Flags().Changed("workspace")); err != nil {
					return err
				}
				repairSSHKey, err := resolveSSHAuthorizedKey(
					sshAuthorizedKey,
					cmd.Flags().Changed("ssh-authorized-key"),
					sshAuthorizedKeyFile,
					cmd.Flags().Changed("ssh-authorized-key-file"),
				)
				if err != nil {
					return err
				}
				networkName := ""
				if len(args) == 2 {
					networkName = args[1]
				} else {
					networkName, err = currentNetworkName(options)
					if err != nil {
						return err
					}
				}
				return runRemoteRepair(cmd, options, args[0], networkName, component.Environment{OS: targetOS, Role: role, Workspace: workspace, SSHAuthorizedKey: repairSSHKey}, cmd.Flags().Changed("workspace"), repair)
			}
			if repair || repairPlan {
				if err := validateRepairWorkspace(workspace, cmd.Flags().Changed("workspace")); err != nil {
					return err
				}
				repairSSHKey, err := resolveSSHAuthorizedKey(
					sshAuthorizedKey,
					cmd.Flags().Changed("ssh-authorized-key"),
					sshAuthorizedKeyFile,
					cmd.Flags().Changed("ssh-authorized-key-file"),
				)
				if err != nil {
					return err
				}
				plan, err := component.RepairPlan(component.Environment{OS: targetOS, Role: role, Workspace: workspace, SSHAuthorizedKey: repairSSHKey})
				if err != nil {
					return err
				}
				if repair {
					if !yes {
						return fmt.Errorf("refusing to run repair without --yes; inspect steps first with --repair-plan")
					}
					printRepairPlan(cmd.OutOrStdout(), plan)
					return component.RunPlan(plan, options.RepairExecutor)
				}
				printRepairPlan(cmd.OutOrStdout(), plan)
				return nil
			}
			if len(args) > 0 {
				networkName := ""
				if len(args) == 2 {
					networkName = args[1]
				} else {
					var err error
					networkName, err = currentNetworkName(options)
					if err != nil {
						return err
					}
				}
				return runRemoteDoctor(options, cmd.OutOrStdout(), args[0], networkName)
			}
			if _, err := os.Stat(options.ConfigPath); err == nil {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "ok config found")
			} else {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "warn config not found")
			}
			if _, err := os.Stat(options.ConfigPath); err == nil {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "ok local config readable")
			}
			if ssh.Installed() {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "ok ssh command found")
			} else {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "warn ssh command not found")
			}
			if options.Tailnet.Installed() {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "ok private network client found")
			} else {
				_, _ = fmt.Fprintln(cmd.OutOrStdout(), "warn private network client not found")
			}
			for _, managed := range component.Managed() {
				visibility := "internal"
				if managed.PublicCommand {
					visibility = "public"
				}
				_, _ = fmt.Fprintf(cmd.OutOrStdout(), "managed component %s %s %s\n", managed.ID, managed.License, visibility)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&repairPlan, "repair-plan", false, "print CodexDock-managed repair steps")
	cmd.Flags().BoolVar(&repair, "repair", false, "run CodexDock-managed repair steps")
	cmd.Flags().BoolVar(&yes, "yes", false, "confirm repair execution")
	cmd.Flags().BoolVar(&all, "all", false, "check every registered machine in the current network")
	cmd.Flags().StringVar(&targetOS, "target-os", runtime.GOOS, "target operating system for repair plan")
	cmd.Flags().StringVar(&role, "role", "client", "machine role for repair plan: client, controller, or codex-host")
	cmd.Flags().StringVar(&workspace, "workspace", "~/code", "workspace to create for codex-host repair plans")
	cmd.Flags().StringVar(&sshAuthorizedKey, "ssh-authorized-key", "", "public SSH key to add for codex-host repair plans")
	cmd.Flags().StringVar(&sshAuthorizedKeyFile, "ssh-authorized-key-file", "", "path to a public SSH key file to add for codex-host repair plans")
	return cmd
}

func validateRepairWorkspace(workspace string, provided bool) error {
	if provided && strings.TrimSpace(workspace) == "" {
		return fmt.Errorf("--workspace cannot be empty")
	}
	return nil
}

func resolveSSHAuthorizedKey(value string, valueSet bool, file string, fileSet bool) (string, error) {
	value = strings.TrimSpace(value)
	file = strings.TrimSpace(file)
	if valueSet && value == "" {
		return "", fmt.Errorf("--ssh-authorized-key cannot be blank")
	}
	if fileSet && file == "" {
		return "", fmt.Errorf("--ssh-authorized-key-file cannot be blank")
	}
	if value != "" && file != "" {
		return "", fmt.Errorf("use either --ssh-authorized-key or --ssh-authorized-key-file, not both")
	}
	if file == "" {
		return value, nil
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return "", fmt.Errorf("read SSH authorized key file %s: %w", file, err)
	}
	content := string(data)
	if strings.TrimSpace(content) == "" {
		return "", fmt.Errorf("SSH authorized key file %s is empty", file)
	}
	firstLine, _, _ := strings.Cut(content, "\n")
	firstLine = strings.TrimSpace(firstLine)
	if firstLine == "" {
		return "", fmt.Errorf("SSH authorized key file %s first line is empty", file)
	}
	key := firstLine
	return key, nil
}

func runRemoteRepair(cmd *cobra.Command, options Options, machineName, networkName string, env component.Environment, workspaceSet bool, execute bool) error {
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	if !workspaceSet {
		env.Workspace = machine.Workspace
	}
	plan, err := component.RepairPlan(env)
	if err != nil {
		return err
	}
	target := targetFor(machine)
	printRemoteRepairPlan(cmd.OutOrStdout(), machine.Name, target, plan)
	if !execute {
		return nil
	}
	for _, step := range plan.Steps {
		if step.Command == "" {
			continue
		}
		if _, _, err := options.Runner.Run(target, step.Command); err != nil {
			return fmt.Errorf("%s on %s: %w", step.Name, machine.Name, err)
		}
	}
	return nil
}

func runRemoteDoctor(options Options, out io.Writer, machineName, networkName string) error {
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	return runRemoteReadiness(options.Runner, out, machine, networkName, true)
}

func runRemoteReadiness(runner ssh.Runner, out io.Writer, machine config.Machine, networkName string, verbose bool) error {
	target := targetFor(machine)
	if err := runRemoteCheck(runner, target, "true"); err != nil {
		return fmt.Errorf("cannot connect to %s; run codexdock machines %s or verify SSH to %s", machine.Name, networkName, sshTargetSpec(target))
	}
	if verbose {
		_, _ = fmt.Fprintf(out, "ok can connect to %s\n", machine.Name)
	}

	if err := runRemoteCheck(runner, target, "command -v tmux"); err != nil {
		return fmt.Errorf("tmux not found on %s; fix: ssh %s 'sudo apt update && sudo apt install -y tmux'", machine.Name, sshTargetSpec(target))
	}
	if verbose {
		_, _ = fmt.Fprintln(out, "ok remote tmux found")
	}

	agent := agentBinary(machine.AgentCommand)
	agentCommand := "command -v " + shellCommandWord(agent)
	if err := runRemoteCheck(runner, target, agentCommand); err != nil {
		return fmt.Errorf("%s not found on %s; verify with %s, install it, or update the registered agent command", agent, machine.Name, remoteSSHCommand(target, agentCommand))
	}
	if verbose {
		_, _ = fmt.Fprintf(out, "ok remote %s found\n", agent)
	}

	workspacePath := remoteWorkspacePath(machine.Workspace)
	if err := runRemoteCheck(runner, target, "test -d "+workspacePath); err != nil {
		return fmt.Errorf("workspace %s not found on %s; create it with %s or update the registered workspace", machine.Workspace, machine.Name, remoteSSHCommand(target, "mkdir -p "+workspacePath))
	}
	if verbose {
		_, _ = fmt.Fprintln(out, "ok workspace exists")
	}
	return nil
}

func runRemoteDoctorForNetwork(options Options, out io.Writer, networkName string) error {
	cfg, err := config.NewStore(options.ConfigPath).Load()
	if err != nil {
		return err
	}
	network, ok := cfg.Networks[networkName]
	if !ok {
		return fmt.Errorf("network %s not found", networkName)
	}
	names := make([]string, 0, len(network.Machines))
	for name := range network.Machines {
		names = append(names, name)
	}
	sort.Strings(names)
	if len(names) == 0 {
		return fmt.Errorf("no machines registered in network %s", networkName)
	}
	failures := 0
	for _, name := range names {
		if err := runRemoteDoctor(options, out, name, networkName); err != nil {
			failures++
			_, _ = fmt.Fprintf(out, "fail %s: %v\n", name, err)
		}
	}
	if failures > 0 {
		return fmt.Errorf("doctor --all failed for %d machine(s)", failures)
	}
	return nil
}

func runRemoteCheck(runner ssh.Runner, target ssh.Target, command string) error {
	_, _, err := runner.Run(target, command)
	return err
}

func agentBinary(agentCommand string) string {
	fields := strings.Fields(agentCommand)
	if len(fields) == 0 {
		return "codex"
	}
	return fields[0]
}

func remoteWorkspacePath(workspace string) string {
	if workspace == "" {
		workspace = "~/code"
	}
	if workspace == "~" {
		return "$HOME"
	}
	if rest, ok := strings.CutPrefix(workspace, "~/"); ok {
		if isShellSafePath(rest) {
			return "$HOME/" + rest
		}
		return "$HOME/" + tmux.ShellQuote(rest)
	}
	return tmux.ShellQuote(workspace)
}

func shellCommandWord(value string) string {
	if isShellSafePath(value) {
		return value
	}
	return tmux.ShellQuote(value)
}

func isShellSafePath(value string) bool {
	for _, r := range value {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '/' || r == '_' || r == '-' || r == '.' {
			continue
		}
		return false
	}
	return value != ""
}

func sshTargetSpec(target ssh.Target) string {
	host := target.Host
	if target.User != "" {
		host = target.User + "@" + host
	}
	if target.Port != 0 && target.Port != 22 {
		return fmt.Sprintf("-p %d %s", target.Port, host)
	}
	return host
}

func remoteSSHCommand(target ssh.Target, command string) string {
	return fmt.Sprintf("ssh %s %s", sshTargetSpec(target), tmux.ShellQuote(command))
}

func codexCommand(options Options) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "codex",
		Short: "Control Codex sessions through registered machines",
	}
	cmd.AddCommand(codexSessionsCommand(options))
	cmd.AddCommand(codexStartCommand(options))
	cmd.AddCommand(codexAttachCommand(options))
	cmd.AddCommand(codexSendCommand(options))
	cmd.AddCommand(codexLogsCommand(options))
	cmd.AddCommand(codexStopCommand(options))
	return cmd
}

func topLevelSessionsCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "sessions [machine]",
		Short: "List Codex tmux sessions in the current network",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			networkName, err := currentNetworkName(options)
			if err != nil {
				return err
			}
			if len(args) == 0 {
				return runCodexSessionsForNetwork(options, cmd.OutOrStdout(), networkName)
			}
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			return runCodexSessions(options, cmd.OutOrStdout(), machineName, networkName)
		},
	}
}

func topLevelStartCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "start <machine>",
		Short: "Start the Codex tmux session in the current network",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := currentNetworkName(options)
			if err != nil {
				return err
			}
			return runCodexStart(options, cmd.OutOrStdout(), machineName, networkName, fmt.Sprintf("codexdock attach %s", machineName))
		},
	}
}

func topLevelAttachCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "attach <machine>",
		Short: "Attach to the Codex tmux session in the current network",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := currentNetworkName(options)
			if err != nil {
				return err
			}
			return runCodexAttach(options, machineName, networkName, fmt.Sprintf("codexdock start %s", machineName))
		},
	}
}

func topLevelSendCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "send <machine> <prompt...>",
		Short: "Send a prompt to Codex in the current network",
		Args:  cobra.MinimumNArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := currentNetworkName(options)
			if err != nil {
				return err
			}
			return runCodexSend(options, cmd.OutOrStdout(), cmd.ErrOrStderr(), machineName, networkName, strings.Join(args[1:], " "), fmt.Sprintf("codexdock start %s", machineName))
		},
	}
}

func topLevelLogsCommand(options Options) *cobra.Command {
	var lines int
	cmd := &cobra.Command{
		Use:   "logs <machine>",
		Short: "Print recent Codex tmux output in the current network",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := currentNetworkName(options)
			if err != nil {
				return err
			}
			return runCodexLogs(options, cmd.OutOrStdout(), machineName, networkName, lines, fmt.Sprintf("codexdock start %s", machineName))
		},
	}
	cmd.Flags().IntVar(&lines, "lines", 200, "lines to capture")
	return cmd
}

func topLevelStopCommand(options Options) *cobra.Command {
	var yes bool
	var force bool
	cmd := &cobra.Command{
		Use:   "stop <machine>",
		Short: "Stop the Codex tmux session in the current network",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if !yes && !force {
				return fmt.Errorf("refusing to stop a Codex session without --yes or --force")
			}
			machineName, err := normalizeRequiredName("machine name", args[0])
			if err != nil {
				return err
			}
			networkName, err := currentNetworkName(options)
			if err != nil {
				return err
			}
			return runCodexStop(options, cmd.OutOrStdout(), cmd.ErrOrStderr(), machineName, networkName)
		},
	}
	cmd.Flags().BoolVar(&yes, "yes", false, "confirm stopping the Codex tmux session")
	cmd.Flags().BoolVar(&force, "force", false, "confirm stopping the Codex tmux session")
	return cmd
}

func codexSessionsCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "sessions <machine> <network>",
		Short: "List Codex tmux sessions",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, networkName, err := normalizeTargetArgs(args[0], args[1])
			if err != nil {
				return err
			}
			return runCodexSessions(options, cmd.OutOrStdout(), machineName, networkName)
		},
	}
}

func runCodexSessions(options Options, out io.Writer, machineName, networkName string) error {
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	stdout, stderr, err := options.Runner.Run(targetFor(machine), tmux.ListSessionsCommand())
	sessions := tmux.ParseListSessions(stdout)
	if err != nil && len(sessions) == 0 && !tmuxListMeansNoSessions(stderr+stdout) {
		return err
	}
	if len(sessions) == 0 {
		printNoSessions(out, machine.Name, networkName)
		return nil
	}
	_, _ = fmt.Fprintln(out, "DEVICE\tSESSION\tSTATUS")
	for _, session := range sessions {
		_, _ = fmt.Fprintf(out, "%s\t%s\t%s\n", machine.Name, session.Name, session.Status)
	}
	return nil
}

func runCodexSessionsForNetwork(options Options, out io.Writer, networkName string) error {
	cfg, err := config.NewStore(options.ConfigPath).Load()
	if err != nil {
		return err
	}
	network, ok := cfg.Networks[networkName]
	if !ok {
		return fmt.Errorf("network %s not found", networkName)
	}
	names := make([]string, 0, len(network.Machines))
	for name := range network.Machines {
		names = append(names, name)
	}
	sort.Strings(names)
	_, _ = fmt.Fprintln(out, "DEVICE\tSESSION\tSTATUS")
	rows := 0
	failures := 0
	for _, name := range names {
		machine, err := resolve(options, networkName, name)
		if err != nil {
			failures++
			_, _ = fmt.Fprintf(out, "fail %s: %v\n", name, err)
			continue
		}
		stdout, stderr, err := options.Runner.Run(targetFor(machine), tmux.ListSessionsCommand())
		sessions := tmux.ParseListSessions(stdout)
		if err != nil && len(sessions) == 0 && !tmuxListMeansNoSessions(stderr+stdout) {
			failures++
			_, _ = fmt.Fprintf(out, "fail %s: list sessions on %s: %v\n", machine.Name, machine.Name, err)
			continue
		}
		for _, session := range sessions {
			_, _ = fmt.Fprintf(out, "%s\t%s\t%s\n", machine.Name, session.Name, session.Status)
			rows++
		}
	}
	if rows == 0 && failures == 0 {
		_, _ = fmt.Fprintf(out, "No tmux sessions found in %s.\n", networkName)
		if len(names) > 0 {
			_, _ = fmt.Fprintf(out, "Run:\n  codexdock start %s\n", names[0])
		}
	}
	if failures > 0 {
		return fmt.Errorf("sessions failed for %d machine(s)", failures)
	}
	return nil
}

func codexStartCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "start <machine> <network>",
		Short: "Start the Codex tmux session",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, networkName, err := normalizeTargetArgs(args[0], args[1])
			if err != nil {
				return err
			}
			return runCodexStart(options, cmd.OutOrStdout(), machineName, networkName, fmt.Sprintf("codexdock codex attach %s %s", machineName, networkName))
		},
	}
}

func runCodexStart(options Options, out io.Writer, machineName, networkName, attachCommand string) error {
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	if err := runRemoteReadiness(options.Runner, io.Discard, machine, networkName, false); err != nil {
		return err
	}
	hasSessionCommand, err := tmux.HasSessionCommand(machine.SessionName)
	if err != nil {
		return err
	}
	if _, _, err := options.Runner.Run(targetFor(machine), hasSessionCommand); err == nil {
		_, _ = fmt.Fprintf(out, "Codex session '%s' already running on %s.\n", machine.SessionName, machine.Name)
		_, _ = fmt.Fprintf(out, "Attach:\n  %s\n", attachCommand)
		return nil
	}
	command, err := tmux.StartSessionCommand(machine.SessionName, machine.Workspace, machine.AgentCommand)
	if err != nil {
		return err
	}
	_, _, err = options.Runner.Run(targetFor(machine), command)
	if err != nil {
		return err
	}
	_, _ = fmt.Fprintf(out, "Started Codex session '%s' on %s.\n", machine.SessionName, machine.Name)
	_, _ = fmt.Fprintf(out, "Attach:\n  %s\n", attachCommand)
	return nil
}

func codexAttachCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "attach <machine> <network>",
		Short: "Attach to the Codex tmux session",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, networkName, err := normalizeTargetArgs(args[0], args[1])
			if err != nil {
				return err
			}
			return runCodexAttach(options, machineName, networkName, fmt.Sprintf("codexdock codex start %s %s", machineName, networkName))
		},
	}
}

func runCodexAttach(options Options, machineName, networkName, startCommand string) error {
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	if err := ensureCodexSessionExists(options.Runner, machine, startCommand); err != nil {
		return err
	}
	command, err := tmux.AttachCommand(machine.SessionName)
	if err != nil {
		return err
	}
	return options.Runner.RunInteractive(targetFor(machine), command)
}

func codexSendCommand(options Options) *cobra.Command {
	return &cobra.Command{
		Use:   "send <machine> <network> <prompt...>",
		Short: "Send a prompt to Codex without attaching",
		Args:  cobra.MinimumNArgs(3),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, networkName, err := normalizeTargetArgs(args[0], args[1])
			if err != nil {
				return err
			}
			return runCodexSend(options, cmd.OutOrStdout(), cmd.ErrOrStderr(), machineName, networkName, strings.Join(args[2:], " "), fmt.Sprintf("codexdock codex start %s %s", machineName, networkName))
		},
	}
}

func runCodexSend(options Options, out, errOut io.Writer, machineName, networkName, prompt, startCommand string) error {
	if strings.TrimSpace(prompt) == "" {
		return fmt.Errorf("prompt cannot be empty")
	}
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	if err := ensureCodexSessionExists(options.Runner, machine, startCommand); err != nil {
		return err
	}
	if promptLength := utf8.RuneCountInString(prompt); promptLength > longPromptWarningThreshold {
		_, _ = fmt.Fprintf(errOut, "warning: prompt is %d characters; consider attaching for large input.\n", promptLength)
	}
	command, err := tmux.SendKeysCommand(machine.SessionName, prompt)
	if err != nil {
		return err
	}
	_, _, err = options.Runner.Run(targetFor(machine), command)
	if err != nil {
		return err
	}
	_, _ = fmt.Fprintf(out, "Sent prompt to %s on %s.\n", machine.SessionName, machine.Name)
	return nil
}

func ensureCodexSessionExists(runner ssh.Runner, machine config.Machine, startCommand string) error {
	hasSessionCommand, err := tmux.HasSessionCommand(machine.SessionName)
	if err != nil {
		return err
	}
	if _, _, err := runner.Run(targetFor(machine), hasSessionCommand); err != nil {
		return fmt.Errorf("Codex session '%s' not found on %s; run %s", machine.SessionName, machine.Name, startCommand)
	}
	return nil
}

func codexLogsCommand(options Options) *cobra.Command {
	var lines int
	cmd := &cobra.Command{
		Use:   "logs <machine> <network>",
		Short: "Print recent Codex tmux output",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			machineName, networkName, err := normalizeTargetArgs(args[0], args[1])
			if err != nil {
				return err
			}
			return runCodexLogs(options, cmd.OutOrStdout(), machineName, networkName, lines, fmt.Sprintf("codexdock codex start %s %s", machineName, networkName))
		},
	}
	cmd.Flags().IntVar(&lines, "lines", 200, "lines to capture")
	return cmd
}

func runCodexLogs(options Options, out io.Writer, machineName, networkName string, lines int, startCommand string) error {
	if lines <= 0 {
		return fmt.Errorf("--lines must be positive")
	}
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	if err := ensureCodexSessionExists(options.Runner, machine, startCommand); err != nil {
		return err
	}
	command, err := tmux.CapturePaneCommand(machine.SessionName, lines)
	if err != nil {
		return err
	}
	stdout, _, err := options.Runner.Run(targetFor(machine), command)
	if err != nil {
		return err
	}
	_, _ = fmt.Fprint(out, stdout)
	return nil
}

func codexStopCommand(options Options) *cobra.Command {
	var yes bool
	var force bool
	cmd := &cobra.Command{
		Use:   "stop <machine> <network>",
		Short: "Stop the Codex tmux session",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			if !yes && !force {
				return fmt.Errorf("refusing to stop a Codex session without --yes or --force")
			}
			machineName, networkName, err := normalizeTargetArgs(args[0], args[1])
			if err != nil {
				return err
			}
			return runCodexStop(options, cmd.OutOrStdout(), cmd.ErrOrStderr(), machineName, networkName)
		},
	}
	cmd.Flags().BoolVar(&yes, "yes", false, "confirm stopping the Codex tmux session")
	cmd.Flags().BoolVar(&force, "force", false, "confirm stopping the Codex tmux session")
	return cmd
}

func runCodexStop(options Options, out, errOut io.Writer, machineName, networkName string) error {
	machine, err := resolve(options, networkName, machineName)
	if err != nil {
		return err
	}
	hasSessionCommand, err := tmux.HasSessionCommand(machine.SessionName)
	if err != nil {
		return err
	}
	if _, _, err := options.Runner.Run(targetFor(machine), hasSessionCommand); err != nil {
		_, _ = fmt.Fprintf(out, "Codex session '%s' is not running on %s.\n", machine.SessionName, machine.Name)
		return nil
	}
	command, err := tmux.KillSessionCommand(machine.SessionName)
	if err != nil {
		return err
	}
	_, _ = fmt.Fprintf(errOut, "warning: Codex session '%s' on %s will be killed.\n", machine.SessionName, machine.Name)
	_, _, err = options.Runner.Run(targetFor(machine), command)
	if err != nil {
		return err
	}
	_, _ = fmt.Fprintf(out, "Stopped Codex session '%s' on %s.\n", machine.SessionName, machine.Name)
	return nil
}

func resolve(options Options, networkName, machineName string) (config.Machine, error) {
	var err error
	networkName, err = normalizeRequiredName("network name", networkName)
	if err != nil {
		return config.Machine{}, err
	}
	machineName, err = normalizeRequiredName("machine name", machineName)
	if err != nil {
		return config.Machine{}, err
	}
	cfg, err := config.NewStore(options.ConfigPath).Load()
	if err != nil {
		return config.Machine{}, err
	}
	machine, err := cfg.ResolveMachine(networkName, machineName)
	if err != nil {
		return config.Machine{}, err
	}
	return resolveTailnetHost(options.Tailnet, networkName, machine)
}

func normalizeTargetArgs(machineArg, networkArg string) (string, string, error) {
	machineName, err := normalizeRequiredName("machine name", machineArg)
	if err != nil {
		return "", "", err
	}
	networkName, err := normalizeRequiredName("network name", networkArg)
	if err != nil {
		return "", "", err
	}
	return machineName, networkName, nil
}

func networkFromArgsOrCurrent(options Options, args []string) (string, error) {
	if len(args) > 0 {
		return normalizeRequiredName("network name", args[0])
	}
	return currentNetworkName(options)
}

func currentNetworkName(options Options) (string, error) {
	cfg, err := config.NewStore(options.ConfigPath).Load()
	if err != nil {
		return "", err
	}
	if cfg.CurrentNetwork == "" {
		if len(cfg.Networks) == 1 {
			for name := range cfg.Networks {
				return name, nil
			}
		}
		if len(cfg.Networks) > 1 {
			names := make([]string, 0, len(cfg.Networks))
			for name := range cfg.Networks {
				names = append(names, name)
			}
			sort.Strings(names)
			return "", fmt.Errorf("no current network configured; multiple networks available (%s); use an explicit network command", strings.Join(names, ", "))
		}
		return "", fmt.Errorf("no current network configured; run codexdock init or use an explicit network command")
	}
	if _, ok := cfg.Networks[cfg.CurrentNetwork]; !ok {
		return "", fmt.Errorf("current network %s not found in config", cfg.CurrentNetwork)
	}
	return cfg.CurrentNetwork, nil
}

func targetFor(machine config.Machine) ssh.Target {
	return ssh.Target{Host: machine.Host, User: machine.SSHUser, Port: machine.SSHPort}
}

func currentUsername() string {
	current, err := user.Current()
	if err != nil || current.Username == "" {
		return os.Getenv("USER")
	}
	return current.Username
}

func discoverSelfHost(client tailnet.Client, fallback string) string {
	if client != nil {
		if status, err := client.Status(); err == nil && status.Self.IP != "" {
			return status.Self.IP
		}
	}
	return fallback
}

func tailnetStatus(client tailnet.Client) (tailnet.Status, bool) {
	if client == nil {
		return tailnet.Status{}, false
	}
	status, err := client.Status()
	if err != nil {
		return tailnet.Status{}, false
	}
	return status, true
}

func machineDisplayStatus(status tailnet.Status, live bool, machine config.Machine) (string, string) {
	host := machine.Host
	if !live {
		return host, "unknown"
	}
	peer, ok := resolveMachinePeer(status, machine)
	if !ok {
		return host, "unknown"
	}
	if peer.IP != "" {
		host = peer.IP
	}
	if peer.Online {
		return host, "online"
	}
	return host, "offline"
}

func resolveTailnetHost(client tailnet.Client, networkName string, machine config.Machine) (config.Machine, error) {
	status, live := tailnetStatus(client)
	if !live {
		if needsTailnetResolution(machine) {
			return config.Machine{}, fmt.Errorf("private network status unavailable for %s; run codexdock doctor", machine.Name)
		}
		return machine, nil
	}
	peer, ok := resolveMachinePeer(status, machine)
	if !ok {
		if needsTailnetResolution(machine) {
			return config.Machine{}, fmt.Errorf("%s is not reachable on private network; run codexdock machines %s", machine.Name, networkName)
		}
		return machine, nil
	}
	if !peer.Online {
		return config.Machine{}, fmt.Errorf("%s is offline on private network; run codexdock machines %s", machine.Name, networkName)
	}
	if peer.IP != "" {
		machine.Host = peer.IP
	}
	return machine, nil
}

func resolveMachinePeer(status tailnet.Status, machine config.Machine) (tailnet.Peer, bool) {
	if peer, ok := status.Resolve(machine.Name); ok && peer.IP != "" {
		return peer, true
	}
	if peer, ok := status.Resolve(machine.Host); ok && peer.IP != "" {
		return peer, true
	}
	return tailnet.Peer{}, false
}

func needsTailnetResolution(machine config.Machine) bool {
	host := strings.TrimSpace(machine.Host)
	return host == "" || host == machine.Name || net.ParseIP(host) == nil && !strings.Contains(host, ".")
}

func printRepairPlan(out io.Writer, plan component.Plan) {
	_, _ = fmt.Fprintf(out, "CodexDock repair plan (%s)\n", plan.Role)
	for i, step := range plan.Steps {
		_, _ = fmt.Fprintf(out, "%d. %s\n", i+1, step.Name)
		if step.Description != "" {
			_, _ = fmt.Fprintf(out, "   %s\n", step.Description)
		}
		if step.Command != "" {
			_, _ = fmt.Fprintf(out, "   %s\n", step.Command)
		}
	}
}

func printRemoteRepairPlan(out io.Writer, machineName string, target ssh.Target, plan component.Plan) {
	_, _ = fmt.Fprintf(out, "CodexDock remote repair plan for %s (%s)\n", machineName, plan.Role)
	for i, step := range plan.Steps {
		_, _ = fmt.Fprintf(out, "%d. %s\n", i+1, step.Name)
		if step.Description != "" {
			_, _ = fmt.Fprintf(out, "   %s\n", step.Description)
		}
		if step.Command != "" {
			_, _ = fmt.Fprintf(out, "   %s\n", remoteSSHCommand(target, step.Command))
		}
	}
}

func printJoinGuidance(out io.Writer, network config.Network) {
	if network.ControlURL == "" {
		return
	}
	_, _ = fmt.Fprintf(out, "Invite another machine:\n  codexdock invite %s\n", network.Name)
}

func tmuxListMeansNoSessions(output string) bool {
	output = strings.ToLower(output)
	return strings.Contains(output, "no server running") || strings.Contains(output, "failed to connect")
}

func printNoSessions(out io.Writer, machineName, networkName string) {
	_, _ = fmt.Fprintf(out, "No tmux sessions found on %s.\n", machineName)
	_, _ = fmt.Fprintf(out, "Run:\n  codexdock codex start %s %s\n", machineName, networkName)
}
