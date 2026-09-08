# Plan: Agent Helper
Planned: 2026-09-07 · Executor protocol: v1 (embedded below, binding)

## Objective
Create a local `agent` command that opens a normal persistent shell for the current folder, keeps that shell alive through terminal closure with tmux, and controls an Amphetamine closed-display session without directly changing macOS power settings.

## Success criteria (re-verified by the FINAL checkpoint)
1. Running `agent` from any directory creates or reattaches to exactly one deterministic tmux session for that directory and presents a normal interactive shell; it does not automatically launch Claude, Codex, or a custom TUI.
2. A process started inside the managed shell continues after Ghostty closes or detaches, and running `agent` again from the same directory returns to that same process and terminal state.
3. `agent wake`, `agent sleep`, `agent status`, `agent list`, and `agent stop` control and explain session state idempotently, with Amphetamine remaining active while another managed project session exists.
4. On this M1 Pro MacBook Pro, the documented closed-lid canary advances while the lid is closed and Amphetamine protection is active, then normal sleep behavior can be restored.
5. Installation changes only this project and `~/.local/bin/agent`; the implementation never invokes `sudo` or `pmset disablesleep`, and the existing Ghostty configuration remains valid.

## Non-goals
- No Herdr integration, remote execution, cloud host, agent orchestration, or session restoration after reboot.
- No custom TUI, dashboard, pane manager, or replacement for normal Claude/Codex interfaces.
- No automatic launching of `claude`, `codex`, or any other agent.
- No custom privileged helper and no direct edits to `/etc`, sudoers, or global macOS power settings.
- No changes to Ghostty keybindings, the existing three-modifier Hyper key, or Hyper-I/J/K/L navigation.
- No promise that work survives shutdown, reboot, application crashes, thermal shutdown, or battery exhaustion.

## Context & constraints
Environment: M1 Pro MacBook Pro, macOS 26.5.2, zsh, Ghostty · Stack: POSIX shell, tmux, AppleScript via `/usr/bin/osascript`, Amphetamine · Deadline: none · Access: local user access; App Store and administrator authentication may require the user

Verified local facts at planning time: `tmux`, `osascript`, Claude Code, Codex, Python, PyYAML, and `~/.local/bin` are available; `agent` is unclaimed; Amphetamine is not installed. The project root is `/Users/randyren/Developer/agent helper`.

## Assumptions
- A1: Amphetamine's AppleScript dictionary still supports start, status, and end on macOS 26.5.2 → validated at CP-1.
- A2: Amphetamine Closed-Display Mode plus Power Protect works on this exact M1 Pro/macOS combination → validated by a physical lid-close canary at CP-1; no implementation proceeds without the result.
- A3: `~/.local/bin` remains on interactive zsh PATH → re-verified at CP-4.
- A4: Default tmux prefix behavior is acceptable; the tool will print detach guidance but will not alter `~/.tmux.conf` → accepted constraint.
- A5: Amphetamine's configured low-battery cutoff is the safety backstop if the CLI or terminal exits unexpectedly → validated during CP-1's human gate.

## Command contract

```text
agent                Create or reattach to this folder's normal tmux shell
agent status         Show this folder's session, Amphetamine state, power source, and readiness
agent list           List all sessions managed by Agent Helper
agent stop            Stop this folder's tmux session; release wake protection only if it was the last managed session
agent stop --all      Stop all managed sessions, then release wake protection
agent wake            Start Amphetamine idempotently without entering tmux
agent sleep           End Amphetamine only when no managed sessions remain
agent sleep --force   End Amphetamine despite managed sessions, with a warning
agent doctor          Check dependencies, Power Protect, AppleScript control, install path, and closed-lid verification freshness
agent help            Print concise usage
```

The default `agent` path prints a short status banner and then hands control to tmux. Inside tmux, the user gets an ordinary login shell and types `claude`, `codex`, tests, servers, or anything else normally.

## Phase map
P1 → P2 → P3 → P4 → CP-FINAL. P1 is the feasibility gate; no later phase begins if actual closed-lid behavior is unverified.

---

## Phase 1 — Verified Amphetamine closed-lid substrate
**Goal:** Amphetamine is installed, safely configured, scriptable, and proven to keep a real local canary advancing with the lid closed on this machine.
**Depends on:** —
**Tasks:**
1. Install Amphetamine from the Mac App Store. Stop for user authentication if required.
2. Configure its default non-trigger session to allow display sleep, prevent system sleep when the built-in display is closed, and end automatically at or below 30% battery.
3. Install Amphetamine Power Protect only through Amphetamine's documented prompt. Record its exact installed files; do not create or widen sudoers rules manually.
4. Capture the preimplementation SHA-256 of the active Ghostty config in `.verification/ghostty-config.sha256`.
5. Create `scripts/verify_amphetamine.sh` to test app presence, AppleScript start/status/end, Power Protect presence on Apple silicon, and guaranteed cleanup after the test.
6. Create `scripts/closed_lid_canary.sh` with `prepare`, `verify`, and `cleanup` operations. `prepare` starts a timestamped background counter and Amphetamine; after the user closes the lid for at least 120 seconds and reopens it, `verify` proves the counter advanced by at least 90 seconds and records model, OS build, and Amphetamine version in a local verification marker.
7. Document the physical test and rollback in `docs/amphetamine-setup.md`, including how to end the Amphetamine session and uninstall Power Protect from Amphetamine.
**Deliverables:** `scripts/verify_amphetamine.sh`, `scripts/closed_lid_canary.sh`, `docs/amphetamine-setup.md`, `.verification/ghostty-config.sha256`, a machine-specific closed-lid verification marker.

```yaml
checkpoint:
  id: CP-1
  phase: "Verified Amphetamine closed-lid substrate"
  halt: true
  max_attempts: 3
  human_gate: true
  checks:
    - name: amphetamine-automation-live
      run: "sh scripts/verify_amphetamine.sh"
      expect: "exit 0"
    - name: physical-closed-lid-canary
      run: "sh scripts/closed_lid_canary.sh verify"
      expect: "exit 0"
    - name: setup-and-rollback-documented
      run: "test -s docs/amphetamine-setup.md && rg -q '30%|Power Protect|closed lid|rollback|uninstall' docs/amphetamine-setup.md"
      expect: "exit 0"
```

---

## Phase 2 — Normal-shell walking skeleton
**Goal:** An uninstalled `bin/agent` can create and reattach deterministic per-directory tmux sessions while controlling Amphetamine through a small adapter.
**Depends on:** CP-1 passed and approved
**Tasks:**
1. Implement `bin/agent` as a POSIX shell executable with the command contract above, initially covering default launch, `wake`, `sleep`, `status`, `list`, and `help`.
2. Derive a safe deterministic tmux session name from the canonical absolute directory: readable basename plus a short hash. Store the canonical root in tmux session environment metadata so `list` never guesses from a name.
3. Put AppleScript calls behind `lib/amphetamine.sh`; make start/end/status idempotent and return actionable errors when Amphetamine is absent or automation is denied.
4. Put tmux discovery and session creation behind `lib/sessions.sh`. The default command must use a login shell and must not run Claude or Codex automatically.
5. Add command-contract tests using fake `tmux` and `osascript` executables, including spaces, punctuation, symlinks, duplicate basenames, and repeated invocation from the same canonical path.
**Deliverables:** `bin/agent`, `lib/amphetamine.sh`, `lib/sessions.sh`, `tests/test_agent_contract.sh`, `tests/test_session_mapping.sh`, test fixtures.

```yaml
checkpoint:
  id: CP-2
  phase: "Normal-shell walking skeleton"
  halt: true
  max_attempts: 3
  human_gate: false
  checks:
    - name: shell-syntax
      run: "sh -n bin/agent lib/amphetamine.sh lib/sessions.sh"
      expect: "exit 0"
    - name: command-contract
      run: "sh tests/test_agent_contract.sh"
      expect: "exit 0"
    - name: deterministic-session-mapping
      run: "sh tests/test_session_mapping.sh"
      expect: "exit 0"
```

---

## Phase 3 — Shared wake-state and failure safety
**Goal:** Multiple managed projects, partial failures, and repeated commands cannot silently disable another session's protection or leave the tool claiming protection that is not active.
**Depends on:** CP-2 passed
**Tasks:**
1. Implement `stop`, `stop --all`, `sleep`, and `sleep --force`. Derive active managed sessions from tmux metadata instead of maintaining a fragile reference counter.
2. Make `agent sleep` refuse while managed sessions remain; `--force` must emit a visible warning and never kill tmux sessions.
3. Make `agent stop` release Amphetamine only after proving no managed sessions remain. A failed AppleScript call must produce a nonzero exit and truthful status.
4. Add `agent doctor` checks for executable dependencies, App installation, AppleScript authorization, Power Protect on Apple silicon, power source, battery percentage, and whether the recorded closed-lid proof matches the current model/OS/Amphetamine version.
5. Warn when starting on battery and clearly display the configured low-battery safety dependency; never claim that Amphetamine's GUI settings were verified unless CP-1's machine-specific marker is current.
6. Handle interrupts and concurrent invocations without corrupting project metadata. Do not call `sudo`, write sudoers, or invoke `pmset disablesleep` anywhere.
7. Add failure-injection tests for missing app, denied automation, dead tmux server, multiple sessions, stale verification marker, low battery, and forced sleep.
**Deliverables:** completed command lifecycle, `lib/doctor.sh`, `tests/test_safety.sh`, `tests/test_concurrency.sh`.

```yaml
checkpoint:
  id: CP-3
  phase: "Shared wake-state and failure safety"
  halt: true
  max_attempts: 3
  human_gate: false
  checks:
    - name: safety-behavior
      run: "sh tests/test_safety.sh"
      expect: "exit 0"
    - name: concurrent-lifecycle
      run: "sh tests/test_concurrency.sh"
      expect: "exit 0"
    - name: no-privileged-power-bypass
      run: "! rg -n '(^|[^[:alnum:]_])(sudo)([^[:alnum:]_]|$)|pmset[[:space:]]+.*disablesleep|/private/etc/sudoers|/etc/sudoers' bin lib scripts/install.sh"
      expect: "exit 0"
```

---

## Phase 4 — Surgical installation and live reattachment
**Goal:** `agent` is installed on the existing PATH and its real tmux/Amphetamine path works without changing shell or Ghostty configuration.
**Depends on:** CP-3 passed
**Tasks:**
1. Create an idempotent `scripts/install.sh` that installs or updates only the symlink `~/.local/bin/agent` pointing to this project's `bin/agent`. Refuse to overwrite a non-symlink or a symlink owned by another target.
2. Add an uninstall mode that removes only a symlink resolving to this project and leaves all tmux sessions and Amphetamine settings untouched unless explicitly requested.
3. Add `tests/test_e2e.sh` using isolated temporary directories and uniquely prefixed tmux sessions; verify two directories with the same basename do not collide and all test sessions are cleaned up.
4. Add `tests/test_reattach_e2e.sh`: start a counter in a detached managed session, disconnect the client, re-enter through `agent`, and prove the original PID and counter survived.
5. Add `tests/test_all.sh` and a concise `README.md` covering normal use, tmux detach (`Ctrl-B`, then `D`), safety, limitations, and uninstall.
6. Run Ghostty's config validator and compare the active config hash captured in Phase 1; do not edit Ghostty or zsh configuration.
**Deliverables:** `scripts/install.sh`, installed `~/.local/bin/agent` symlink, E2E tests, `README.md`.

```yaml
checkpoint:
  id: CP-4
  phase: "Surgical installation and live reattachment"
  halt: true
  max_attempts: 3
  human_gate: false
  checks:
    - name: installation-is-correct
      run: "sh scripts/install.sh --check && zsh -lic 'test \"$(command -v agent)\" = \"/Users/randyren/.local/bin/agent\"'"
      expect: "exit 0"
    - name: real-local-e2e
      run: "sh tests/test_e2e.sh"
      expect: "exit 0"
    - name: real-reattach-e2e
      run: "sh tests/test_reattach_e2e.sh"
      expect: "exit 0"
    - name: ghostty-config-preserved
      run: "test \"$(shasum -a 256 '/Users/randyren/Library/Application Support/com.mitchellh.ghostty/config' | awk '{print $1}')\" = \"$(cat .verification/ghostty-config.sha256)\" && /Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config"
      expect: "exit 0"
```

---

## Final checkpoint
```yaml
checkpoint:
  id: CP-FINAL
  phase: "End-to-end acceptance"
  halt: true
  max_attempts: 2
  human_gate: true
  checks:
    - name: normal-shell-and-command-contract
      run: "sh tests/test_all.sh && agent doctor"
      expect: "exit 0"
    - name: terminal-close-persistence
      run: "sh tests/test_reattach_e2e.sh"
      expect: "exit 0"
    - name: shared-wake-lifecycle
      run: "sh tests/test_safety.sh && sh tests/test_concurrency.sh"
      expect: "exit 0"
    - name: current-machine-closed-lid-proof
      run: "sh scripts/closed_lid_canary.sh verify"
      expect: "exit 0"
    - name: surgical-install-and-ghostty-preservation
      run: "sh scripts/install.sh --check && test \"$(shasum -a 256 '/Users/randyren/Library/Application Support/com.mitchellh.ghostty/config' | awk '{print $1}')\" = \"$(cat .verification/ghostty-config.sha256)\" && /Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config"
      expect: "exit 0"
```

The final human gate must additionally observe this exact workflow: enter a project, run `agent`, type either `claude` or `codex` manually, detach or close Ghostty, reopen Ghostty, rerun `agent` in the same project, and confirm the same agent conversation is present. No custom TUI should appear.

---

## Executor Protocol v1 (binding)

1. Execute phases in dependency order. Never start a phase whose dependencies' checkpoints have not PASSED.
2. At every `checkpoint` with `halt: true`: STOP. Run every check exactly as written — when `scripts/checkpoint_runner.py` is present, use `python scripts/checkpoint_runner.py run <CP-ID>`, which executes the checks and prints the report. Capture the real output.
3. Emit a Checkpoint Report (format below) with per-check PASS/FAIL and pasted evidence. A claim of "done" without pasted output is not done.
4. All checks pass → mark the phase complete and proceed. Any check fails → diagnose, fix the *work*, then re-run ALL checks in the checkpoint, not just the failed one.
5. After `max_attempts` failed attempts: halt the entire run. Emit a Failure Report (format below) and escalate. Do not continue to later phases.
6. Never edit, weaken, skip, or reinterpret a check to make it pass. If you believe a check itself is wrong, halt and say so explicitly in a Failure Report — changing the verifier is a human decision, not an executor decision.
7. `human_gate: true` → even on all-pass, stop and wait for explicit human approval before proceeding.
8. The project is complete only when CP-FINAL passes. CP-FINAL re-verifies the Success criteria from a clean state.

### Checkpoint Report format
```
## Checkpoint Report — CP-<n> (<phase>) — attempt <k>/<max>
- <check-name>: PASS|FAIL
  $ <command>
  <first/last relevant lines of real output>
Verdict: PASS → proceeding to <next phase> | FAIL → <next action>
```

### Failure Report format
```
## Failure Report — CP-<n> after <max> attempts
Failing checks + evidence: <...>
What was tried: <...>
Current hypothesis: <...>
Needed to unblock: <decision | access | fix to check | scope change>
```
