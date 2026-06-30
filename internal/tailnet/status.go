package tailnet

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

type Client interface {
	Installed() bool
	Status() (Status, error)
	Join(JoinOptions) error
}

type SystemClient struct{}

type Status struct {
	Self  Peer
	Peers map[string]Peer
}

type Peer struct {
	HostName string
	DNSName  string
	IP       string
	Online   bool
}

type JoinOptions struct {
	ControlURL string
	AuthKey    string
	Hostname   string
}

type rawStatus struct {
	Self rawPeer            `json:"Self"`
	Peer map[string]rawPeer `json:"Peer"`
}

type rawPeer struct {
	HostName    string   `json:"HostName"`
	DNSName     string   `json:"DNSName"`
	TailscaleIP []string `json:"TailscaleIPs"`
	Online      bool     `json:"Online"`
}

func ParseStatusJSON(data []byte) (Status, error) {
	var raw rawStatus
	if err := json.Unmarshal(data, &raw); err != nil {
		return Status{}, err
	}
	status := Status{
		Self:  normalizePeer(raw.Self),
		Peers: map[string]Peer{},
	}
	for _, peer := range raw.Peer {
		normalized := normalizePeer(peer)
		key := normalized.HostName
		if key == "" {
			key = strings.TrimSuffix(normalized.DNSName, ".")
		}
		if key == "" {
			continue
		}
		status.Peers[key] = normalized
	}
	return status, nil
}

func Installed() bool {
	return SystemClient{}.Installed()
}

func (SystemClient) Installed() bool {
	_, err := exec.LookPath("tailscale")
	return err == nil
}

func (SystemClient) Status() (Status, error) {
	output, err := exec.Command("tailscale", "status", "--json").Output()
	if err != nil {
		return Status{}, err
	}
	return ParseStatusJSON(output)
}

func (SystemClient) Join(options JoinOptions) error {
	args, err := JoinArgs(options)
	if err != nil {
		return err
	}
	output, err := exec.Command("tailscale", args...).CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			return err
		}
		return fmt.Errorf("%w: %s", err, message)
	}
	return nil
}

func JoinArgs(options JoinOptions) ([]string, error) {
	if strings.TrimSpace(options.ControlURL) == "" {
		return nil, fmt.Errorf("control URL is required")
	}
	args := []string{"up", "--login-server=" + strings.TrimSpace(options.ControlURL)}
	if strings.TrimSpace(options.AuthKey) != "" {
		args = append(args, "--auth-key="+strings.TrimSpace(options.AuthKey))
	}
	if strings.TrimSpace(options.Hostname) != "" {
		args = append(args, "--hostname="+strings.TrimSpace(options.Hostname))
	}
	return args, nil
}

func (s Status) Resolve(name string) (Peer, bool) {
	if name == "" {
		return Peer{}, false
	}
	if matchesPeer(s.Self, name) {
		return s.Self, true
	}
	if peer, ok := s.Peers[name]; ok {
		return peer, true
	}
	for _, peer := range s.Peers {
		if matchesPeer(peer, name) {
			return peer, true
		}
	}
	return Peer{}, false
}

func normalizePeer(peer rawPeer) Peer {
	hostName := peer.HostName
	dnsName := strings.TrimSuffix(peer.DNSName, ".")
	if hostName == "" && dnsName != "" {
		hostName = strings.Split(dnsName, ".")[0]
	}
	ip := ""
	if len(peer.TailscaleIP) > 0 {
		ip = peer.TailscaleIP[0]
	}
	return Peer{
		HostName: hostName,
		DNSName:  dnsName,
		IP:       ip,
		Online:   peer.Online,
	}
}

func matchesPeer(peer Peer, name string) bool {
	if peer.HostName == name {
		return true
	}
	if peer.DNSName == name {
		return true
	}
	if peer.IP == name {
		return true
	}
	dnsShort := strings.Split(peer.DNSName, ".")[0]
	return dnsShort == name
}
