package control

import (
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

type Issuer interface {
	Installed() bool
	IssueInvite(InviteOptions) (Invite, error)
	ProvisionNetwork(NetworkOptions) error
}

type SystemIssuer struct{}

type InviteOptions struct {
	Network   string
	TTL       string
	Reusable  bool
	Ephemeral bool
}

type Invite struct {
	Key string
}

type NetworkOptions struct {
	Name string
}

var ErrUserNotFound = errors.New("headscale user not found")

func (SystemIssuer) Installed() bool {
	_, err := exec.LookPath("headscale")
	return err == nil
}

func (SystemIssuer) ProvisionNetwork(options NetworkOptions) error {
	userArgs, err := ListUsersArgs(options.Name)
	if err != nil {
		return err
	}
	userOutput, err := exec.Command("headscale", userArgs...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(userOutput))
		if message == "" {
			return err
		}
		return fmt.Errorf("%w: %s", err, message)
	}
	if _, err := ParseUserID(userOutput, options.Name); err == nil {
		return nil
	} else if !errors.Is(err, ErrUserNotFound) {
		return err
	}

	args, err := ProvisionNetworkArgs(options)
	if err != nil {
		return err
	}
	output, err := exec.Command("headscale", args...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			return err
		}
		return fmt.Errorf("%w: %s", err, message)
	}
	return nil
}

func (SystemIssuer) IssueInvite(options InviteOptions) (Invite, error) {
	userArgs, err := ListUsersArgs(options.Network)
	if err != nil {
		return Invite{}, err
	}
	userOutput, err := exec.Command("headscale", userArgs...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(userOutput))
		if message == "" {
			return Invite{}, err
		}
		return Invite{}, fmt.Errorf("%w: %s", err, message)
	}
	userID, err := ParseUserID(userOutput, options.Network)
	if err != nil {
		return Invite{}, err
	}
	args, err := PreAuthKeyArgs(options, userID)
	if err != nil {
		return Invite{}, err
	}
	output, err := exec.Command("headscale", args...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			return Invite{}, err
		}
		return Invite{}, fmt.Errorf("%w: %s", err, message)
	}
	key, err := ParseInviteKey(output)
	if err != nil {
		return Invite{}, err
	}
	return Invite{Key: key}, nil
}

func ListUsersArgs(network string) ([]string, error) {
	network = strings.TrimSpace(network)
	if network == "" {
		return nil, fmt.Errorf("network is required")
	}
	return []string{"users", "list", "--name", network, "--output=json"}, nil
}

func PreAuthKeyArgs(options InviteOptions, userID string) ([]string, error) {
	network := strings.TrimSpace(options.Network)
	if network == "" {
		return nil, fmt.Errorf("network is required")
	}
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return nil, fmt.Errorf("user ID is required")
	}
	ttl := strings.TrimSpace(options.TTL)
	if ttl == "" {
		ttl = "24h"
	}
	args := []string{
		"preauthkeys",
		"create",
		"--user", userID,
		"--expiration", ttl,
	}
	if options.Reusable {
		args = append(args, "--reusable")
	}
	if options.Ephemeral {
		args = append(args, "--ephemeral")
	}
	args = append(args, "--output=json")
	return args, nil
}

func ProvisionNetworkArgs(options NetworkOptions) ([]string, error) {
	name := strings.TrimSpace(options.Name)
	if name == "" {
		return nil, fmt.Errorf("network name is required")
	}
	return []string{"users", "create", name}, nil
}

func ParseInviteKey(output []byte) (string, error) {
	var raw map[string]any
	if err := json.Unmarshal(output, &raw); err == nil {
		for _, field := range []string{"key", "Key", "authKey", "AuthKey"} {
			if value, ok := raw[field].(string); ok && strings.TrimSpace(value) != "" {
				return strings.TrimSpace(value), nil
			}
		}
	}

	text := strings.TrimSpace(string(output))
	if text == "" {
		return "", fmt.Errorf("invite output did not contain an enrollment key")
	}
	keyPattern := regexp.MustCompile(`(?m)(?:key|Key|authKey|AuthKey)[:=]\s*([^\s]+)`)
	if match := keyPattern.FindStringSubmatch(text); len(match) == 2 {
		return strings.TrimSpace(match[1]), nil
	}
	fields := strings.Fields(text)
	if len(fields) == 1 {
		return fields[0], nil
	}
	return "", fmt.Errorf("invite output did not contain an enrollment key")
}

func ParseUserID(output []byte, network string) (string, error) {
	network = strings.TrimSpace(network)
	if network == "" {
		return "", fmt.Errorf("network is required")
	}
	var raw any
	if err := json.Unmarshal(output, &raw); err != nil {
		return "", fmt.Errorf("headscale user list output was not JSON: %w", err)
	}
	for _, user := range collectUserObjects(raw) {
		name := stringField(user, "name", "Name")
		if name != network {
			continue
		}
		id := idField(user, "id", "Id", "ID")
		if id == "" {
			return "", fmt.Errorf("headscale user %s did not include an ID", network)
		}
		return id, nil
	}
	return "", fmt.Errorf("%w: %s", ErrUserNotFound, network)
}

func collectUserObjects(raw any) []map[string]any {
	switch value := raw.(type) {
	case []any:
		users := make([]map[string]any, 0, len(value))
		for _, item := range value {
			if user, ok := item.(map[string]any); ok {
				users = append(users, user)
			}
		}
		return users
	case map[string]any:
		for _, key := range []string{"users", "Users"} {
			if nested, ok := value[key]; ok {
				return collectUserObjects(nested)
			}
		}
		if stringField(value, "name", "Name") != "" || idField(value, "id", "Id", "ID") != "" {
			return []map[string]any{value}
		}
	}
	return nil
}

func stringField(fields map[string]any, names ...string) string {
	for _, name := range names {
		if value, ok := fields[name].(string); ok {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func idField(fields map[string]any, names ...string) string {
	for _, name := range names {
		switch value := fields[name].(type) {
		case string:
			return strings.TrimSpace(value)
		case float64:
			if value >= 0 && value == float64(uint64(value)) {
				return strconv.FormatUint(uint64(value), 10)
			}
		}
	}
	return ""
}
