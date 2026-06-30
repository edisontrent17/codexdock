package tailnet_test

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/tailnet"
)

func TestParseTailscaleStatusJSON(t *testing.T) {
	status, err := tailnet.ParseStatusJSON([]byte(`{
		"Self": {"HostName": "macbook", "TailscaleIPs": ["100.64.0.1"], "Online": true},
		"Peer": {
			"abc": {"HostName": "homepc", "TailscaleIPs": ["100.64.0.2"], "Online": true},
			"def": {"DNSName": "workstation.tailnet.ts.net.", "TailscaleIPs": ["100.64.0.3"], "Online": false}
		}
	}`))

	require.NoError(t, err)
	require.Equal(t, "macbook", status.Self.HostName)
	require.Equal(t, "100.64.0.2", status.Peers["homepc"].IP)
	require.True(t, status.Peers["homepc"].Online)
	require.Equal(t, "100.64.0.3", status.Peers["workstation"].IP)
	require.False(t, status.Peers["workstation"].Online)
}

func TestResolveFindsSelfPeerAndDNSAlias(t *testing.T) {
	status, err := tailnet.ParseStatusJSON([]byte(`{
		"Self": {"HostName": "macbook", "TailscaleIPs": ["100.64.0.1"], "Online": true},
		"Peer": {
			"abc": {"DNSName": "homepc.personal.ts.net.", "TailscaleIPs": ["100.64.0.2"], "Online": true}
		}
	}`))
	require.NoError(t, err)

	self, ok := status.Resolve("macbook")
	require.True(t, ok)
	require.Equal(t, "100.64.0.1", self.IP)

	peer, ok := status.Resolve("homepc")
	require.True(t, ok)
	require.Equal(t, "100.64.0.2", peer.IP)

	_, ok = status.Resolve("missing")
	require.False(t, ok)
}

func TestResolveFindsPeerByIP(t *testing.T) {
	status, err := tailnet.ParseStatusJSON([]byte(`{
		"Self": {"HostName": "macbook", "TailscaleIPs": ["100.64.0.1"], "Online": true},
		"Peer": {
			"abc": {"HostName": "windows-wsl", "TailscaleIPs": ["100.64.0.2"], "Online": true}
		}
	}`))
	require.NoError(t, err)

	peer, ok := status.Resolve("100.64.0.2")

	require.True(t, ok)
	require.Equal(t, "windows-wsl", peer.HostName)
	require.True(t, peer.Online)
}

func TestResolveMatchesHostAndDNSAliasesCaseInsensitively(t *testing.T) {
	status, err := tailnet.ParseStatusJSON([]byte(`{
		"Self": {"HostName": "MacBook", "TailscaleIPs": ["100.64.0.1"], "Online": true},
		"Peer": {
			"abc": {"HostName": "Windows-WSL", "DNSName": "Windows-WSL.Personal.TS.Net.", "TailscaleIPs": ["100.64.0.2"], "Online": true}
		}
	}`))
	require.NoError(t, err)

	self, ok := status.Resolve("macbook")
	require.True(t, ok)
	require.Equal(t, "100.64.0.1", self.IP)

	peer, ok := status.Resolve("windows-wsl")
	require.True(t, ok)
	require.Equal(t, "100.64.0.2", peer.IP)

	peer, ok = status.Resolve("windows-wsl.personal.ts.net")
	require.True(t, ok)
	require.Equal(t, "100.64.0.2", peer.IP)
}

func TestJoinArgsUseControlURLAuthKeyAndHostname(t *testing.T) {
	args, err := tailnet.JoinArgs(tailnet.JoinOptions{
		ControlURL: "https://control.example",
		AuthKey:    "tskey-auth",
		Hostname:   "macbook",
	})

	require.NoError(t, err)
	require.Equal(t, []string{
		"up",
		"--login-server=https://control.example",
		"--auth-key=tskey-auth",
		"--hostname=macbook",
	}, args)
}
