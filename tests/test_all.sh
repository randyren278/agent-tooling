#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

sh "$PROJECT_ROOT/tests/test_agent_contract.sh"
sh "$PROJECT_ROOT/tests/test_session_mapping.sh"
sh "$PROJECT_ROOT/tests/test_safety.sh"
sh "$PROJECT_ROOT/tests/test_concurrency.sh"
sh "$PROJECT_ROOT/tests/test_install.sh"
sh "$PROJECT_ROOT/tests/test_e2e.sh"
sh "$PROJECT_ROOT/tests/test_reattach_e2e.sh"
printf '%s\n' 'test_all: PASS'
