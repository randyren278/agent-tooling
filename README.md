# Agent Helper

`agent` opens one ordinary persistent tmux shell for the current folder and keeps Amphetamine active while managed shells exist. Inside that shell, run `claude`, `codex`, servers, tests, or any other command normally. Agent Helper does not auto-launch an agent or replace its interface.

## Install

Prerequisites are macOS, tmux, and a configured Amphetamine installation with Closed-Display Mode, Power Protect, and the 30% low-battery cutoff described in [`docs/amphetamine-setup.md`](docs/amphetamine-setup.md).

```sh
sh scripts/install.sh
agent doctor
```

The installer creates only `~/.local/bin/agent`. It will not overwrite another command or edit shell, Ghostty, Amphetamine, or macOS power configuration.

## Use

```text
agent                 enter or reattach to this folder's shell
agent status          show this folder and wake state
agent list            list all managed shells
agent stop            stop this folder; sleep when it is the last one
agent stop --all      stop every managed shell, then sleep
agent wake            start Amphetamine without entering tmux
agent sleep           sleep only when no managed shells remain
agent sleep --force   end Amphetamine but leave tmux shells running
agent doctor          verify local readiness
```

Detach without stopping work by pressing `Ctrl-B`, releasing both keys, then pressing `D`. Run `agent` again from the same folder to return to the same shell.

Keep the Mac on a hard, ventilated surface when using closed-display mode, especially on battery. The 30% Amphetamine cutoff is a safety backstop, not a guarantee against shutdown, crashes, thermal limits, or battery exhaustion. Sessions do not survive a reboot.

## Uninstall

```sh
sh scripts/install.sh --uninstall
```

Uninstall removes only this project's symlink. It intentionally leaves tmux sessions and Amphetamine settings untouched; use `agent stop --all` first if you want to end managed work and release wake protection.
