package main

import (
	"fmt"
	"os"

	"github.com/trentsoftware/codexdock/internal/cli"
)

func main() {
	if err := cli.New(cli.Options{}).Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
