#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$(mktemp -d "${TMPDIR:-/tmp}/dram-api-visibility.XXXXXX")"
trap 'rm -rf "$project"' EXIT

cat >"$project/ard.toml" <<EOF
name = "dram_api_visibility"
ard = ">= 0.1.0"

[dependencies]
dram = { path = "$root" }
EOF

cat >"$project/main.ard" <<'EOF'
use dram
use go:context as go_context

fn tamper(next: dram::Next) {
  next.store.state.ran = false
}

fn unwrap(context: go_context::Context) {
  context.store.raw.Err()
}

fn continue_from_route(request: dram::Request, response: mut dram::Response) {
  request.next(response)
}

fn main() {}
EOF

if ard-dev check "$project/main.ard" >"$project/output" 2>&1; then
  echo "opaque Dram internals were externally mutable" >&2
  exit 1
fi

[[ "$(grep -c 'Undefined field' "$project/output")" == "2" ]]
[[ "$(grep -c 'Undefined method' "$project/output")" == "1" ]]
echo "API visibility check passed"
