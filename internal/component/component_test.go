package component_test

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/component"
)

func TestManagedComponentsPreserveUpstreamLicensesAndStayInternal(t *testing.T) {
	components := component.Managed()

	byID := map[string]component.Component{}
	for _, c := range components {
		byID[c.ID] = c
	}

	require.Equal(t, "BSD-3-Clause", byID["tailscale"].License)
	require.Equal(t, "https://github.com/tailscale/tailscale", byID["tailscale"].Upstream)
	require.False(t, byID["tailscale"].PublicCommand)

	require.Equal(t, "BSD-3-Clause", byID["headscale"].License)
	require.Equal(t, "https://github.com/juanfont/headscale", byID["headscale"].Upstream)
	require.False(t, byID["headscale"].PublicCommand)
}
