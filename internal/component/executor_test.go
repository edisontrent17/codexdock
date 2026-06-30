package component_test

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/trentsoftware/codexdock/internal/component"
)

func TestRunPlanExecutesCommandsInOrder(t *testing.T) {
	plan := component.Plan{
		Role: "client",
		Steps: []component.Step{
			{Name: "first", Command: "echo first"},
			{Name: "second", Command: "echo second"},
		},
	}
	executor := &recordingExecutor{}

	require.NoError(t, component.RunPlan(plan, executor))

	require.Equal(t, []string{"echo first", "echo second"}, executor.commands)
}

func TestRunPlanStopsOnCommandFailure(t *testing.T) {
	plan := component.Plan{
		Role: "client",
		Steps: []component.Step{
			{Name: "first", Command: "echo first"},
			{Name: "second", Command: "echo second"},
		},
	}
	executor := &recordingExecutor{failAt: "echo first"}

	err := component.RunPlan(plan, executor)

	require.ErrorContains(t, err, "first")
	require.Equal(t, []string{"echo first"}, executor.commands)
}

type recordingExecutor struct {
	commands []string
	failAt   string
}

func (e *recordingExecutor) Run(command string) error {
	e.commands = append(e.commands, command)
	if command == e.failAt {
		return errors.New("boom")
	}
	return nil
}
