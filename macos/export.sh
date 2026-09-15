#!/usr/bin/env bash
# Run on MacBookPro16,1 macOS. Wraps t2-touchid-linux tools/macos exporters.
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
exec "$ROOT/bin/mbp16-1" macos export "$@"
