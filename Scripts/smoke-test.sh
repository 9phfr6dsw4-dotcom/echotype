#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/EchoType.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
    printf 'App bundle does not exist: %s\n' "$APP_BUNDLE" >&2
    exit 1
fi

trap 'pkill -x EchoTypeApp >/dev/null 2>&1 || true' EXIT
open -n -g "$APP_BUNDLE"

for _ in {1..10}; do
    if pgrep -x EchoTypeApp >/dev/null 2>&1; then
        printf 'Launch smoke test passed; EchoTypeApp started.\n'
        exit 0
    fi
    sleep 1
done

printf 'EchoTypeApp did not remain running after launch.\n' >&2
exit 1
