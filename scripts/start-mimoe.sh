#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# start-mimoe.sh
#
# Start a local mimOE instance from the project-local .mimoe/ copy.
# Uses .mimoe/ as the --work-dir. The .edge/ inside is symlinked back to
# ~/.mimoe/.edge (by init.sh) so all existing addons and deployed mims
# are available.
#
# Usage:
#   ./scripts/start-mimoe.sh                   Start on default port (8083)
#   MIMOE_PORT=9090 ./scripts/start-mimoe.sh   Start on custom port
#
# The script waits until mimOE is ready (MCM API responds), then prints
# the connection details. mimOE runs in the foreground — Ctrl+C to stop.
#
# Run from project root:  ./scripts/start-mimoe.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIMOE_DIR="$PROJECT_DIR/.mimoe"
PORT="${MIMOE_PORT:-8083}"

# ── Preflight checks ─────────────────────────────────────────────────────────

if [ ! -x "$MIMOE_DIR/bin/mimoe" ]; then
  echo "ERROR: mimOE binary not found at $MIMOE_DIR/bin/mimoe"
  echo "Run ./scripts/init.sh first."
  exit 1
fi

if [ ! -f "$MIMOE_DIR/mimoe.lic" ]; then
  echo "ERROR: mimOE license not found at $MIMOE_DIR/mimoe.lic"
  echo "Run ./scripts/init.sh first."
  exit 1
fi

# Check if port is already in use
if lsof -ti:"$PORT" > /dev/null 2>&1; then
  echo "ERROR: Port $PORT is already in use."
  echo "Either stop the existing process or use a different port:"
  echo "  MIMOE_PORT=9090 ./scripts/start-mimoe.sh"
  exit 1
fi

# Verify .edge symlink
if [ -L "$MIMOE_DIR/.edge" ]; then
  echo "Using shared .edge -> $(readlink "$MIMOE_DIR/.edge")"
elif [ -d "$MIMOE_DIR/.edge" ]; then
  echo "WARNING: .edge is a local directory (not symlinked — addons may be missing)"
else
  echo "WARNING: .edge does not exist — mimOE will create a fresh one (no addons)"
fi

# ── Load API keys ────────────────────────────────────────────────────────────

if [ -f "$MIMOE_DIR/mimoe-api-key.env" ]; then
  set -a
  source "$MIMOE_DIR/mimoe-api-key.env"
  set +a
  echo "Loaded API keys from .mimoe/mimoe-api-key.env"
fi

# ── Start mimOE ──────────────────────────────────────────────────────────────

echo ""
echo "Starting mimOE..."
echo "  Binary:    $MIMOE_DIR/bin/mimoe"
echo "  Work dir:  $MIMOE_DIR"
echo "  License:   $MIMOE_DIR/mimoe.lic"
echo "  Port:      $PORT"
echo ""

# Start in background so we can poll for readiness
"$MIMOE_DIR/bin/mimoe" \
  --work-dir "$MIMOE_DIR" \
  --edge-config-file "$MIMOE_DIR/mimoe.lic" \
  --api-port "$PORT" &

MIMOE_PID=$!

# ── Wait for readiness ───────────────────────────────────────────────────────

echo "Waiting for mimOE to be ready (PID: $MIMOE_PID)..."

DEADLINE=$((SECONDS + 30))
READY=false

while [ $SECONDS -lt $DEADLINE ]; do
  if ! kill -0 "$MIMOE_PID" 2>/dev/null; then
    echo "ERROR: mimOE process exited unexpectedly."
    echo "Check .mimoe/.edge/logs/mimoe.log for details."
    exit 1
  fi

  if curl -sf "http://localhost:$PORT/mcm/v1/mims" -H "Authorization: Bearer ${MCM_API_KEY:-}" > /dev/null 2>&1; then
    READY=true
    break
  fi

  sleep 0.5
done

if [ "$READY" = false ]; then
  echo "ERROR: mimOE did not become ready within 30s."
  echo "Check .mimoe/.edge/logs/mimoe.log for details."
  kill "$MIMOE_PID" 2>/dev/null || true
  exit 1
fi

echo ""
echo "mimOE is ready."
echo ""
echo "  MCM API:  http://localhost:$PORT/mcm/v1"
echo "  Logs:     .mimoe/.edge/logs/mimoe.log"
if [ -n "${MCM_API_KEY:-}" ]; then
  echo "  API Key:  $MCM_API_KEY"
fi
echo ""
echo "Press Ctrl+C to stop mimOE."
echo ""

# ── Foreground — wait for Ctrl+C ─────────────────────────────────────────────

trap 'echo ""; echo "Stopping mimOE (PID: $MIMOE_PID)..."; kill "$MIMOE_PID" 2>/dev/null; wait "$MIMOE_PID" 2>/dev/null; echo "Done."' INT TERM

wait "$MIMOE_PID"
