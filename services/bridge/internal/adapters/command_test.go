package adapters

import (
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
		"-o StrictHostKeyChecking=no",
		"-o UserKnownHostsFile=/dev/null",
		"-o LogLevel=ERROR",
		" user@server wake-desktop",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("hardenSSHCommand() = %q, missing %q", got, want)
		}
	}
}

func TestHardenSSHCommandLeavesNonSSHCommandAlone(t *testing.T) {
	const command = "wake-desktop"
	if got := hardenSSHCommand(command); got != command {
		t.Fatalf("hardenSSHCommand() = %q", got)
	}
}
