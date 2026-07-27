#!/usr/bin/env bash
set -euo pipefail

[[ $# -gt 0 ]] || { echo "PrimeTime command is required" >&2; exit 2; }
exec "$@" </dev/null
