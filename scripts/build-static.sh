#!/bin/sh
set -eu

SITE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR="$SITE_DIR/dist"

mkdir -p "$OUTPUT_DIR/.openai"
cp "$SITE_DIR/index.html" "$OUTPUT_DIR/index.html"
cp "$SITE_DIR/sw.js" "$OUTPUT_DIR/sw.js"
cp "$SITE_DIR/manifest.webmanifest" "$OUTPUT_DIR/manifest.webmanifest"
cp "$SITE_DIR/.openai/hosting.json" "$OUTPUT_DIR/.openai/hosting.json"

printf "Static site ready: %s\n" "$OUTPUT_DIR"
