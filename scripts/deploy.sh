#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh
#
# Build, upload, and deploy this mim to a running mimOE instance.
# Reads the mim name from package.json automatically.
#
# Usage:
#   ./scripts/deploy.sh                   Deploy (no rebuild)
#   ./scripts/deploy.sh --build           Rebuild before deploying
#   ./scripts/deploy.sh --redeploy        Remove existing mim first
#   ./scripts/deploy.sh --build --redeploy
#
# Environment:
#   MIMOE_PORT    mimOE API port (default: 8083)
#   MCM_API_KEY   MCM API key (loaded from .mimoe/mimoe-api-key.env)
#   API_KEY       Bearer token for mim client auth (default: test-api-key-123)
#
# Run from project root:  ./scripts/deploy.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIMOE_DIR="$PROJECT_DIR/.mimoe"

# ── Read mim name from package.json ──────────────────────────────────────────

MIM_NAME=$(node -p "require('$PROJECT_DIR/package.json').name")
MIM_IMAGE="${MIM_NAME}-v1"
MIM_CLIENT_ID="api"

# ── Load API keys ────────────────────────────────────────────────────────────
# Load from ~/.mimoe by default, project-local .mimoe/ overrides if present

if [ -f "$HOME/.mimoe/mimoe-api-key.env" ]; then
  set -a
  source "$HOME/.mimoe/mimoe-api-key.env"
  set +a
fi

if [ -f "$MIMOE_DIR/mimoe-api-key.env" ]; then
  set -a
  source "$MIMOE_DIR/mimoe-api-key.env"
  set +a
fi

# ── Configuration ─────────────────────────────────────────────────────────────

PORT="${MIMOE_PORT:-8083}"
MCM_KEY="${MCM_API_KEY:-}"
MIMOE_URL="http://localhost:$PORT"

MIM_API_KEY="${API_KEY:-test-api-key-123}"

DO_BUILD=false
DO_REDEPLOY=false

for arg in "$@"; do
  case "$arg" in
    --build) DO_BUILD=true ;;
    --redeploy) DO_REDEPLOY=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Preflight: mimOE reachable? ──────────────────────────────────────────────

echo "=== deploy $MIM_NAME ==="
echo "mimOE: $MIMOE_URL"
echo ""

if ! curl -sf "$MIMOE_URL/mcm/v1/mims" -H "Authorization: Bearer $MCM_KEY" > /dev/null 2>&1; then
  echo "ERROR: mimOE not reachable at $MIMOE_URL"
  echo "Start mimOE first: ./scripts/start-mimoe.sh"
  exit 1
fi
echo "mimOE is reachable."

# ── Optional: rebuild ─────────────────────────────────────────────────────────

if [ "$DO_BUILD" = true ]; then
  echo ""
  echo "[build] Rebuilding mim bundle..."
  (cd "$PROJECT_DIR" && npm run build 2>&1 | tail -3)
  (cd "$PROJECT_DIR" && npm run package 2>&1 | tail -3)
  echo "[build] Done."
fi

# ── Find mim tar ──────────────────────────────────────────────────────────────

DEPLOY_TAR=$(find "$PROJECT_DIR/deploy" -name '*.tar' 2>/dev/null | head -1)
if [ -z "$DEPLOY_TAR" ]; then
  echo "ERROR: No deploy/*.tar found. Run ./scripts/init.sh or use --build."
  exit 1
fi
echo "Mim tar: $(basename "$DEPLOY_TAR")"

# ── Optional: remove existing mim ────────────────────────────────────────────

if [ "$DO_REDEPLOY" = true ]; then
  echo ""
  echo "[redeploy] Removing existing $MIM_NAME mim and image..."
  curl -sf -X DELETE "$MIMOE_URL/mcm/v1/mims/${MIM_CLIENT_ID}-${MIM_NAME}" \
    -H "Authorization: Bearer $MCM_KEY" > /dev/null 2>&1 || true
  sleep 1
  curl -sf -X DELETE "$MIMOE_URL/mcm/v1/images/${MIM_IMAGE}" \
    -H "Authorization: Bearer $MCM_KEY" > /dev/null 2>&1 || true
  echo "[redeploy] Done."
fi

# ── Upload image ──────────────────────────────────────────────────────────────

echo ""
echo "[1/3] Uploading mim image..."
UPLOAD_RESULT=$(curl -sf -X POST "$MIMOE_URL/mcm/v1/images" \
  -H "Authorization: Bearer $MCM_KEY" \
  -F "image=@$DEPLOY_TAR")

echo "  $UPLOAD_RESULT"

# ── Deploy mim ────────────────────────────────────────────────────────────────

echo ""
echo "[2/3] Deploying $MIM_NAME mim..."

# Build env vars from config/start-example.json if it exists,
# otherwise fall back to minimal defaults.
START_CONFIG=""
if [ -f "$PROJECT_DIR/config/start-example.json" ]; then
  START_CONFIG="$PROJECT_DIR/config/start-example.json"
elif [ -f "$PROJECT_DIR/local/start-example.json" ]; then
  START_CONFIG="$PROJECT_DIR/local/start-example.json"
fi

if [ -n "$START_CONFIG" ]; then
  echo "  Reading env from: $(basename "$(dirname "$START_CONFIG")")/$(basename "$START_CONFIG")"
  # Merge env from start-example.json with MCM.BASE_API_PATH override
  DEPLOY_BODY=$(python3 -c "
import json, sys
with open('$START_CONFIG') as f:
    config = json.load(f)
env = config.get('env', {})
env['MCM.BASE_API_PATH'] = '/$MIM_NAME/v1'
# Replace placeholder values with actual env vars if set
import os
if os.environ.get('API_KEY'):
    env['API_KEY'] = os.environ['API_KEY']
elif env.get('API_KEY', '').startswith('<'):
    env['API_KEY'] = '$MIM_API_KEY'
body = {
    'name': '$MIM_NAME',
    'clientId': '$MIM_CLIENT_ID',
    'image': '$MIM_IMAGE',
    'env': env
}
print(json.dumps(body))
")
else
  echo "  No start-example.json found, using defaults"
  DEPLOY_BODY="{\"name\":\"$MIM_NAME\",\"clientId\":\"$MIM_CLIENT_ID\",\"image\":\"$MIM_IMAGE\",\"env\":{\"MCM.BASE_API_PATH\":\"/$MIM_NAME/v1\",\"API_KEY\":\"$MIM_API_KEY\"}}"
fi

echo "  Env vars:"
echo "$DEPLOY_BODY" | python3 -c "import json,sys; env=json.load(sys.stdin).get('env',{}); [print(f'    {k}={v}') for k,v in env.items()]"

DEPLOY_RESULT=$(curl -sf -X POST "$MIMOE_URL/mcm/v1/mims" \
  -H "Authorization: Bearer $MCM_KEY" \
  -H 'Content-Type: application/json' \
  -d "$DEPLOY_BODY")

echo "  $DEPLOY_RESULT"

# ── Wait for started ──────────────────────────────────────────────────────────

echo ""
echo "[3/3] Waiting for $MIM_NAME to start..."

DEADLINE=$((SECONDS + 30))
STARTED=false

while [ $SECONDS -lt $DEADLINE ]; do
  STATE=$(curl -sf "$MIMOE_URL/mcm/v1/mims" \
    -H "Authorization: Bearer $MCM_KEY" 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin).get('data', [])
for m in data:
    if m.get('name') == '$MIM_NAME':
        print(m.get('state', 'unknown'))
        sys.exit(0)
print('not_found')
" 2>/dev/null || echo "error")

  if [ "$STATE" = "started" ]; then
    STARTED=true
    break
  elif [ "$STATE" = "error" ] || [ "$STATE" = "not_found" ]; then
    :
  fi

  sleep 1
done

echo ""
if [ "$STARTED" = true ]; then
  echo "$MIM_NAME is running."
  echo ""
  echo "  Base URL:  $MIMOE_URL/api/$MIM_NAME/v1"
  echo ""
  # Show available endpoints from swagger if available
  SWAGGER_FILE=""
  if [ -f "$PROJECT_DIR/config/swagger.yml" ]; then
    SWAGGER_FILE="$PROJECT_DIR/config/swagger.yml"
  fi
  if [ -n "$SWAGGER_FILE" ]; then
    echo "  Endpoints:"
    grep -E '^\s+/' "$SWAGGER_FILE" | grep -v '#' | sed 's/[: ]*$//' | sed "s|^[ '\"]*|    $MIMOE_URL/api/$MIM_NAME/v1|" | sed "s|['\"]||g" | sort -u
    echo ""
  fi
  echo "Try it:"
  echo ""
  echo "  curl -s $MIMOE_URL/api/$MIM_NAME/v1 -H 'x-api-key: $MIM_API_KEY' | python3 -m json.tool"
else
  echo "WARNING: $MIM_NAME did not reach 'started' state within 30s."
  echo "Check mimOE logs: .mimoe/.edge/logs/mimoe.log"
fi
