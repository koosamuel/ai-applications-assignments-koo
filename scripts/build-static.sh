#!/bin/sh
set -eu

SITE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$SITE_DIR/scripts/build-worker.mjs"
