package adapters

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

type CommandOptions struct {
	Shell               string
	TimeoutSeconds      int
	MaxOutputBytes      int
	AllowedPrefixes     []string
	AllowShellOperators bool
}

func RunCommandAction(ctx context.Context, command string, opts CommandOptions) (string, error) {
	command = strings.TrimSpace(command)
	if command == "" {
		return "", errors.New("command is required")
	}
	if !commandAllowed(command, opts.AllowedPrefixes) {
		return "", fmt.Errorf("command is not allowed by configured prefixes")
	}
	if !opts.AllowShellOperators && hasShellControlOperators(command) {
		return "", errors.New("shell control operators are disabled for command actions")
	}
	command = hardenSSHCommand(command)

	shell := opts.Shell
	if shell == "" {
		shell = "/bin/sh"
	}
	timeout := time.Duration(opts.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	maxOutput := opts.MaxOutputBytes
	if maxOutput <= 0 {
		maxOutput = 4096
	}

	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(runCtx, shell, "-c", command)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if errors.Is(err, syscall.ESRCH) {
			return nil
		}
		return err
	}
	cmd.WaitDelay = 2 * time.Second
	output := &limitedBuffer{limit: maxOutput}
	cmd.Stdout = output
	cmd.Stderr = output

	err := cmd.Run()
	text := strings.TrimSpace(output.String())
	if output.truncated {
		text = strings.TrimSpace(text + "\n[output truncated]")
	}
	if runCtx.Err() == context.DeadlineExceeded {
		return text, fmt.Errorf("command timed out after %s", timeout)
	}
	if err != nil {
		if text == "" {
			return "", err
		}
		return text, fmt.Errorf("%w: %s", err, text)
	}
	if text == "" {
		text = "command completed"
	}
	return text, nil
}

func commandAllowed(command string, prefixes []string) bool {
	if len(prefixes) == 0 {
		return true
	}
	for _, prefix := range prefixes {
		prefix = strings.TrimSpace(prefix)
		if prefix == "" {
			continue
		}
		if command == prefix {
			return true
		}
		if strings.HasPrefix(command, prefix) && len(command) > len(prefix) && isCommandSeparator(command[len(prefix)]) {
			return true
		}
	}
	return false
}

func isCommandSeparator(value byte) bool {
	return value == ' ' || value == '\t'
}

func hasShellControlOperators(command string) bool {
	if strings.Contains(command, "$(") {
		return true
	}
	return strings.ContainsAny(command, ";&|<>`\n\r")
}

func hardenSSHCommand(command string) string {
	rest, ok := strings.CutPrefix(command, "ssh ")
	if !ok {
		return command
	}
	options := "-n -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"
	return "ssh " + options + " " + rest
}

type limitedBuffer struct {
	buffer    bytes.Buffer
	limit     int
	truncated bool
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if b.limit <= 0 {
		return len(p), nil
	}
	remaining := b.limit - b.buffer.Len()
	if remaining <= 0 {
		b.truncated = true
		return len(p), nil
	}
	if len(p) > remaining {
		b.truncated = true
		_, _ = b.buffer.Write(p[:remaining])
		return len(p), nil
	}
	_, _ = b.buffer.Write(p)
	return len(p), nil
}

func (b *limitedBuffer) String() string {
	return b.buffer.String()
}
