package version

import "fmt"

var (
	Version = "dev"
	Commit  = "unknown"
	Date    = "unknown"
)

func String() string {
	return fmt.Sprintf("codexdock %s\ncommit %s\nbuilt %s\n", Version, Commit, Date)
}
