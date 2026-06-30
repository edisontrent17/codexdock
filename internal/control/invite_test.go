package control_test

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/control"
)

func TestPreAuthKeyArgsUseResolvedUserIDTTLAndOutputJSON(t *testing.T) {
	args, err := control.PreAuthKeyArgs(control.InviteOptions{
		Network:  "personal",
		TTL:      "12h",
		Reusable: true,
	}, "7")

	require.NoError(t, err)
	require.Equal(t, []string{
		"preauthkeys",
		"create",
		"--user", "7",
		"--expiration", "12h",
		"--reusable",
		"--output=json",
	}, args)
}

func TestListUsersArgsUseNetworkNameAndOutputJSON(t *testing.T) {
	args, err := control.ListUsersArgs(" personal ")

	require.NoError(t, err)
	require.Equal(t, []string{"users", "list", "--name", "personal", "--output=json"}, args)
}

func TestParseUserIDFromJSONListOutput(t *testing.T) {
	id, err := control.ParseUserID([]byte(`[{"id":"7","name":"personal"}]`), "personal")

	require.NoError(t, err)
	require.Equal(t, "7", id)
}

func TestParseUserIDFromWrappedJSONListOutput(t *testing.T) {
	id, err := control.ParseUserID([]byte(`{"users":[{"id":7,"name":"personal"}]}`), "personal")

	require.NoError(t, err)
	require.Equal(t, "7", id)
}

func TestParseInviteKeyFromJSONOutput(t *testing.T) {
	key, err := control.ParseInviteKey([]byte(`{"key":"tskey-auth"}`))

	require.NoError(t, err)
	require.Equal(t, "tskey-auth", key)
}

func TestProvisionNetworkArgsCreateControllerUser(t *testing.T) {
	args, err := control.ProvisionNetworkArgs(control.NetworkOptions{Name: "personal"})

	require.NoError(t, err)
	require.Equal(t, []string{"users", "create", "personal"}, args)
}

func TestSystemIssuerProvisionNetworkSkipsCreateWhenUserAlreadyExists(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("fake executable script uses POSIX sh")
	}
	dir := t.TempDir()
	logPath := filepath.Join(dir, "headscale.log")
	writeFakeHeadscale(t, dir, `[{"id":"7","name":"personal"}]`, true)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("HEADSCALE_LOG", logPath)

	err := control.SystemIssuer{}.ProvisionNetwork(control.NetworkOptions{Name: "personal"})

	require.NoError(t, err)
	log := readLog(t, logPath)
	require.Contains(t, log, "users list --name personal --output=json")
	require.NotContains(t, log, "users create personal")
}

func TestSystemIssuerProvisionNetworkCreatesWhenUserIsMissing(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("fake executable script uses POSIX sh")
	}
	dir := t.TempDir()
	logPath := filepath.Join(dir, "headscale.log")
	writeFakeHeadscale(t, dir, `[]`, true)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("HEADSCALE_LOG", logPath)

	err := control.SystemIssuer{}.ProvisionNetwork(control.NetworkOptions{Name: "personal"})

	require.NoError(t, err)
	log := readLog(t, logPath)
	require.Contains(t, log, "users list --name personal --output=json")
	require.Contains(t, log, "users create personal")
	require.Less(t, strings.Index(log, "users list --name personal --output=json"), strings.Index(log, "users create personal"))
}

func writeFakeHeadscale(t *testing.T, dir, userListOutput string, allowCreate bool) {
	t.Helper()
	createExit := "exit 1"
	if allowCreate {
		createExit = "exit 0"
	}
	script := `#!/usr/bin/env sh
set -eu
printf '%s\n' "$*" >>"$HEADSCALE_LOG"
if [ "${1:-}" = "users" ] && [ "${2:-}" = "list" ] && [ "${3:-}" = "--name" ] && [ "${5:-}" = "--output=json" ]; then
  cat <<'JSON'
` + userListOutput + `
JSON
  exit 0
fi
if [ "${1:-}" = "users" ] && [ "${2:-}" = "create" ]; then
  ` + createExit + `
fi
printf 'unexpected headscale command: %s\n' "$*" >&2
exit 1
`
	path := filepath.Join(dir, "headscale")
	require.NoError(t, os.WriteFile(path, []byte(script), 0o755))
}

func readLog(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	return string(data)
}
