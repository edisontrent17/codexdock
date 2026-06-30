package component

type Component struct {
	ID            string
	Name          string
	Binary        string
	License       string
	Upstream      string
	PublicCommand bool
}

func Managed() []Component {
	return []Component{
		{
			ID:            "tailscale",
			Name:          "Tailscale",
			Binary:        "tailscale",
			License:       "BSD-3-Clause",
			Upstream:      "https://github.com/tailscale/tailscale",
			PublicCommand: false,
		},
		{
			ID:            "headscale",
			Name:          "Headscale",
			Binary:        "headscale",
			License:       "BSD-3-Clause",
			Upstream:      "https://github.com/juanfont/headscale",
			PublicCommand: false,
		},
	}
}
