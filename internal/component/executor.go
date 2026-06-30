package component

import (
	"fmt"
	"os"
	"os/exec"
)

type Executor interface {
	Run(command string) error
}

type ShellExecutor struct{}

func RunPlan(plan Plan, executor Executor) error {
	if executor == nil {
		executor = ShellExecutor{}
	}
	for _, step := range plan.Steps {
		if step.Command == "" {
			continue
		}
		if err := executor.Run(step.Command); err != nil {
			return fmt.Errorf("%s: %w", step.Name, err)
		}
	}
	return nil
}

func (ShellExecutor) Run(command string) error {
	cmd := exec.Command("/bin/sh", "-c", command)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
