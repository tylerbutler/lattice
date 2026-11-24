#!/usr/bin/env bash
set -euo pipefail

manifest="$PWD/manifest.toml"
root="$(git rev-parse --show-toplevel)"
output="$root/build/sbom/$(basename "$PWD").cdx.json"

mkdir -p "$root/build/sbom"
cd "$root/tools/audit"
exec gleam run --target erlang -m licence_audit -- sbom \
  --manifest="$manifest" --reproducible --output="$output"
