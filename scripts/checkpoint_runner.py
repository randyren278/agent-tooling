#!/usr/bin/env python3
"""Run and gate YAML checkpoints embedded in PLAN.md."""

import argparse
import io
import json
import re
import subprocess
import sys
import time
from pathlib import Path

STATE = Path(".checkpoints/state.json")
CHECK_TIMEOUT = 600


def die(message, code=3):
    sys.stderr.write(f"checkpoint_runner: {message}\n")
    sys.exit(code)


def yaml_module():
    try:
        import yaml

        return yaml
    except ImportError:
        die("PyYAML is required: pip install pyyaml")


def load_checkpoints(plan):
    path = Path(plan)
    if not path.exists():
        die(f"plan file not found: {plan}")
    yaml = yaml_module()
    checkpoints = []
    seen = set()
    blocks = re.findall(r"```yaml\s*\n(.*?)```", path.read_text(encoding="utf-8"), re.S)
    for block in blocks:
        try:
            data = yaml.safe_load(block)
        except Exception:
            continue
        checkpoint = (data or {}).get("checkpoint") if isinstance(data, dict) else None
        if not isinstance(checkpoint, dict) or not checkpoint.get("id") or not checkpoint.get("checks"):
            continue
        if checkpoint["id"] in seen:
            die(f"duplicate checkpoint id: {checkpoint['id']}")
        seen.add(checkpoint["id"])
        checkpoints.append(checkpoint)
    if not checkpoints:
        die("no checkpoint blocks found in plan")
    return checkpoints


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def entry(state, checkpoint_id):
    return state.setdefault(
        checkpoint_id,
        {"passed": False, "approved": False, "attempts": 0, "last": None},
    )


def cleared(checkpoint, checkpoint_state):
    passed = checkpoint_state.get("passed", False)
    if checkpoint.get("human_gate"):
        passed = passed and checkpoint_state.get("approved", False)
    return passed


def tail(output, lines=10, chars=1000):
    trimmed = "\n".join(output.strip().splitlines()[-lines:])
    return trimmed[-chars:] if len(trimmed) > chars else trimmed


def run_check(check):
    command = check.get("run")
    expected = str(check.get("expect", "exit 0")).strip()
    if not command:
        return False, "no run command", ""
    try:
        process = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=CHECK_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return False, f"timed out after {CHECK_TIMEOUT}s", ""
    output = (process.stdout or "") + (process.stderr or "")
    match = re.fullmatch(r"exit\s+(\d+)", expected)
    if match:
        return (
            process.returncode == int(match.group(1)),
            f"exit {process.returncode} (expected {expected})",
            output,
        )
    found = expected in output
    detail = "found expected text" if found else f"missing expected text: {expected!r}"
    return found, detail, output


def run_checkpoint(checkpoint, state, stream=None):
    stream = stream or sys.stdout
    checkpoint_state = entry(state, checkpoint["id"])
    checkpoint_state["attempts"] += 1
    maximum = int(checkpoint.get("max_attempts", 3))
    write = stream.write
    write(
        f"## Checkpoint Report — {checkpoint['id']} "
        f"({checkpoint.get('phase', '?')}) — attempt "
        f"{checkpoint_state['attempts']}/{maximum}\n"
    )
    all_passed = True
    for check in checkpoint.get("checks", []):
        passed, detail, output = run_check(check)
        all_passed = all_passed and passed
        write(f"- {check.get('name', 'unnamed')}: {'PASS' if passed else 'FAIL'} [{detail}]\n")
        write(f"  $ {check.get('run', '')}\n")
        excerpt = tail(output)
        if excerpt:
            write("  " + excerpt.replace("\n", "\n  ") + "\n")
    checkpoint_state["passed"] = all_passed
    checkpoint_state["last"] = time.strftime("%Y-%m-%d %H:%M:%S")
    if all_passed and checkpoint.get("human_gate") and not checkpoint_state["approved"]:
        write(
            "Verdict: CHECKS PASS — human approval required: "
            f"python scripts/checkpoint_runner.py approve {checkpoint['id']}\n"
        )
    else:
        write(f"Verdict: {'PASS' if all_passed else 'FAIL'}\n")
    save_state(state)
    return all_passed


def failure_report(checkpoint, checkpoint_state):
    return (
        f"## Failure Report — {checkpoint['id']} after "
        f"{checkpoint_state['attempts']} attempts\n"
        f"Checkpoint '{checkpoint.get('phase', '?')}' is still failing at max_attempts. "
        "Halting per Executor Protocol; a human decision is needed "
        "(fix, scope change, or correction to the check itself).\n"
    )


def command_gate(checkpoints, state, strict):
    pending = [
        checkpoint
        for checkpoint in checkpoints
        if not cleared(checkpoint, entry(state, checkpoint["id"]))
    ]
    if not pending:
        print("All checkpoints passed.")
        return 0
    checkpoint = pending[0]
    checkpoint_state = entry(state, checkpoint["id"])
    maximum = int(checkpoint.get("max_attempts", 3))
    if not checkpoint_state["passed"] and checkpoint_state["attempts"] >= maximum:
        sys.stdout.write(failure_report(checkpoint, checkpoint_state))
        return 0
    if checkpoint_state["passed"] and checkpoint.get("human_gate") and not checkpoint_state["approved"]:
        print(
            f"{checkpoint['id']} checks passed; awaiting human approval "
            f"(python scripts/checkpoint_runner.py approve {checkpoint['id']}). Allowing stop."
        )
        return 0
    buffer = io.StringIO()
    passed = run_checkpoint(checkpoint, state, stream=buffer)
    report = buffer.getvalue()
    checkpoint_state = entry(state, checkpoint["id"])
    if passed:
        if checkpoint.get("human_gate") and not checkpoint_state["approved"]:
            sys.stdout.write(report)
            return 0
        remaining = [
            item
            for item in checkpoints
            if not cleared(item, entry(state, item["id"]))
        ]
        if strict and remaining:
            sys.stderr.write(
                report
                + f"\n{checkpoint['id']} passed but the plan is not finished. "
                f"Next: {remaining[0]['id']} ({remaining[0].get('phase', '?')}). "
                "Continue executing the plan; never modify the checks.\n"
            )
            return 2
        sys.stdout.write(report)
        return 0
    if checkpoint_state["attempts"] >= maximum:
        sys.stdout.write(report + failure_report(checkpoint, checkpoint_state))
        return 0
    sys.stderr.write(
        report
        + f"\n{checkpoint['id']} is failing. Fix the work (never the checks) "
        "and complete the phase before stopping.\n"
    )
    return 2


def main():
    parser = argparse.ArgumentParser(description="Run and gate plan checkpoints.")
    parser.add_argument("command", choices=["status", "run", "next", "gate", "approve", "reset"])
    parser.add_argument("target", nargs="?", help="checkpoint id, e.g. CP-1")
    parser.add_argument("--plan", default="PLAN.md")
    parser.add_argument("--strict", action="store_true", help="gate: block until all checkpoints pass")
    arguments = parser.parse_args()

    checkpoints = load_checkpoints(arguments.plan)
    state = load_state()
    by_id = {checkpoint["id"]: checkpoint for checkpoint in checkpoints}

    if arguments.command == "status":
        for checkpoint in checkpoints:
            checkpoint_state = entry(state, checkpoint["id"])
            flag = (
                "PASSED"
                if cleared(checkpoint, checkpoint_state)
                else "awaiting-approval"
                if checkpoint_state["passed"]
                else "pending"
            )
            print(
                f"{checkpoint['id']:>10}  {flag:<18} "
                f"attempts={checkpoint_state['attempts']}  {checkpoint.get('phase', '')}"
            )
        save_state(state)
        return 0
    if arguments.command == "approve":
        if not arguments.target or arguments.target not in by_id:
            die("approve requires a valid checkpoint id")
        entry(state, arguments.target)["approved"] = True
        save_state(state)
        print(f"{arguments.target} approved.")
        return 0
    if arguments.command == "reset":
        if arguments.target:
            state.pop(arguments.target, None)
        else:
            state = {}
        save_state(state)
        print("State reset.")
        return 0
    if arguments.command == "run":
        if not arguments.target or arguments.target not in by_id:
            die("run requires a valid checkpoint id")
        return 0 if run_checkpoint(by_id[arguments.target], state) else 1
    if arguments.command == "next":
        pending = [
            checkpoint
            for checkpoint in checkpoints
            if not cleared(checkpoint, entry(state, checkpoint["id"]))
        ]
        if not pending:
            print("All checkpoints passed.")
            return 0
        return 0 if run_checkpoint(pending[0], state) else 1
    if arguments.command == "gate":
        return command_gate(checkpoints, state, arguments.strict)
    return 3


if __name__ == "__main__":
    sys.exit(main())
