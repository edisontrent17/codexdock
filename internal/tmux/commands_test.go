package tmux_test

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/tmux"
)

func TestSendKeysQuotesPrompt(t *testing.T) {
	got, err := tmux.SendKeysCommand("codex", "it's ok")

	require.NoError(t, err)
	require.Equal(t, "tmux send-keys -t codex 'it'\"'\"'s ok' Enter", got)
}

func TestStartSessionCommandIsIdempotentAndQuoted(t *testing.T) {
	got, err := tmux.StartSessionCommand("codex", "~/code with space", "codex --ask 'now'")

	require.NoError(t, err)
	require.Equal(t, "tmux has-session -t codex 2>/dev/null || tmux new-session -d -s codex -c \"$HOME\"/'code with space' 'codex --ask '\"'\"'now'\"'\"''", got)
}

func TestStartSessionCommandExpandsHomeWorkspace(t *testing.T) {
	got, err := tmux.StartSessionCommand("codex", "~/code", "codex")

	require.NoError(t, err)
	require.Equal(t, "tmux has-session -t codex 2>/dev/null || tmux new-session -d -s codex -c \"$HOME\"/'code' 'codex'", got)
}

func TestHasSessionCommandValidatesName(t *testing.T) {
	got, err := tmux.HasSessionCommand("codex")

	require.NoError(t, err)
	require.Equal(t, "tmux has-session -t codex", got)
}

func TestParseListSessionsOutput(t *testing.T) {
	got := tmux.ParseListSessions("codex: 1 windows (created Sun Jun 28 16:00:00 2026)\nresearch: 1 windows\n")

	require.Equal(t, []tmux.Session{
		{Name: "codex", Status: "running"},
		{Name: "research", Status: "running"},
	}, got)
}

func TestRejectsUnsafeSessionName(t *testing.T) {
	_, err := tmux.SendKeysCommand("codex;rm", "hello")

	require.ErrorContains(t, err, "invalid tmux session name")
}
