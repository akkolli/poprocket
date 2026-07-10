package adapters

import (
	"context"
	"strings"
	"testing"
)

func TestHardenSSHCommandForcesNonInteractiveMode(t *testing.T) {
	got := hardenSSHCommand("ssh user@server wake-desktop")

	for _, want := range []string{
		"ssh -n ",
		"-o BatchMode=yes",
		"-o ConnectTimeout=5",
		"-o ConnectionAttempts=1",
		"-o StrictHostKeyChecking=accept-new",
		"-o LogLevel=ERROR",
		" user@server wake-desktop",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("hardenSSHCommand() = %q, missing %q", got, want)
		}
	}
}

func TestCommandAllowedRequiresTokenBoundary(t *testing.T) {
	if commandAllowed("ssh-evil user@server", []string{"ssh"}) {
		t.Fatal("prefix without a token boundary was accepted")
	}
	if !commandAllowed("ssh user@server", []string{"ssh"}) {
		t.Fatal("valid command prefix was rejected")
	}
}

func TestRunCommandRejectsShellOperatorsByDefault(t *testing.T) {
	_, err := RunCommandAction(context.Background(), "printf safe; printf unsafe", CommandOptions{
		AllowedPrefixes: []string{"printf"},
	})
	if err == nil || !strings.Contains(err.Error(), "control operators") {
		t.Fatalf("error = %v", err)
	}
}

func TestRunCommandAllowsExplicitShellOperators(t *testing.T) {
	output, err := RunCommandAction(context.Background(), "printf safe; printf second", CommandOptions{
		AllowedPrefixes:     []string{"printf"},
		AllowShellOperators: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if output != "safesecond" {
		t.Fatalf("output = %q", output)
	}
}

func TestHardenSSHCommandLeavesNonSSHCommandAlone(t *testing.T) {
	const command = "wake-desktop"
	if got := hardenSSHCommand(command); got != command {
		t.Fatalf("hardenSSHCommand() = %q", got)
	}
}
