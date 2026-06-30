package tmux

import (
	"fmt"
	"regexp"
	"strings"
)

var sessionNamePattern = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

type Session struct {
	Name   string
	Status string
}

func ListSessionsCommand() string {
	return "tmux ls"
}

func HasSessionCommand(session string) (string, error) {
	if err := ValidateSessionName(session); err != nil {
		return "", err
	}
	return fmt.Sprintf("tmux has-session -t %s", session), nil
}

func StartSessionCommand(session, workspace, agentCommand string) (string, error) {
	if err := ValidateSessionName(session); err != nil {
		return "", err
	}
	return fmt.Sprintf(
		"tmux has-session -t %s 2>/dev/null || tmux new-session -d -s %s -c %s %s",
		session,
		session,
		WorkspacePathArg(workspace),
		ShellQuote(agentCommand),
	), nil
}

func AttachCommand(session string) (string, error) {
	if err := ValidateSessionName(session); err != nil {
		return "", err
	}
	return fmt.Sprintf("tmux attach -t %s", session), nil
}

func SendKeysCommand(session, prompt string) (string, error) {
	if err := ValidateSessionName(session); err != nil {
		return "", err
	}
	return fmt.Sprintf("tmux send-keys -t %s %s Enter", session, ShellQuote(prompt)), nil
}

func CapturePaneCommand(session string, lines int) (string, error) {
	if err := ValidateSessionName(session); err != nil {
		return "", err
	}
	if lines <= 0 {
		lines = 200
	}
	return fmt.Sprintf("tmux capture-pane -t %s -p -S -%d", session, lines), nil
}

func KillSessionCommand(session string) (string, error) {
	if err := ValidateSessionName(session); err != nil {
		return "", err
	}
	return fmt.Sprintf("tmux kill-session -t %s", session), nil
}

func ValidateSessionName(session string) error {
	if !sessionNamePattern.MatchString(session) {
		return fmt.Errorf("invalid tmux session name %q", session)
	}
	return nil
}

func ShellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func WorkspacePathArg(workspace string) string {
	workspace = strings.TrimSpace(workspace)
	if workspace == "" {
		workspace = "~/code"
	}
	if workspace == "~" {
		return `"$HOME"`
	}
	if rest, ok := strings.CutPrefix(workspace, "~/"); ok {
		if rest == "" {
			return `"$HOME"`
		}
		return `"$HOME"/` + ShellQuote(rest)
	}
	return ShellQuote(workspace)
}

func ParseListSessions(output string) []Session {
	lines := strings.Split(output, "\n")
	sessions := make([]Session, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		name, _, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		sessions = append(sessions, Session{Name: name, Status: "running"})
	}
	return sessions
}
