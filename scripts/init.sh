#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# init.sh
#
# One-time local setup for this mim. Installs dependencies, builds the mim
# bundle, and sets up the mimOE runtime in the project-local .mimoe/ directory.
#
# mimOE source (in priority order):
#   1. MIMOE_SOURCE env var         — copy from an existing local installation
#   2. ~/.mimoe (if it exists)      — copy from the default global installation
#   3. Auto-download from GitHub    — download the release for this platform
#
# The .mimoe/ directory becomes the mimOE --work-dir.
#
# Environment:
#   MIMOE_SOURCE    Path to an existing mimOE installation to copy from
#   MIMOE_VERSION   mimOE release tag to download (default: v3.20.2)
#
# Run from project root:  ./scripts/init.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIMOE_DEST="$PROJECT_DIR/.mimoe"
MIMOE_VERSION="${MIMOE_VERSION:-v3.20.2}"
MIMOE_REPO="mimik-mimOE/mimOE-SE"

echo "=== mim init ==="
echo "Project dir: $PROJECT_DIR"
echo ""

# ── Step 1: Install dependencies ─────────────────────────────────────────────

echo "[1/4] Installing dependencies..."
if [ -d "$PROJECT_DIR/node_modules" ]; then
  echo "  node_modules/ already exists. Skipping npm install."
  echo "  (Delete node_modules/ and re-run to force reinstall.)"
else
  (cd "$PROJECT_DIR" && npm install --no-audit --no-fund 2>&1 | tail -3)
  echo "  Done."
fi
echo ""

# ── Step 2: Build and package ─────────────────────────────────────────────────

echo "[2/4] Building mim bundle..."
(cd "$PROJECT_DIR" && npm run build 2>&1 | tail -3)
echo "  Done."

echo "  Packaging mim image..."
(cd "$PROJECT_DIR" && npm run package 2>&1 | tail -3)
echo "  Done."
echo ""

# ── Step 3: Set up mimOE runtime ─────────────────────────────────────────────

# Skip if already initialized
if [ -x "$MIMOE_DEST/bin/mimoe" ] && [ -f "$MIMOE_DEST/mimoe.lic" ]; then
  echo "[3/4] mimOE already set up at .mimoe/. Skipping."
  echo "  (Delete .mimoe/ and re-run to force re-setup.)"
  echo ""
else
  # Determine source: explicit env var, ~/.mimoe, or download
  MIMOE_SOURCE="${MIMOE_SOURCE:-}"

  if [ -z "$MIMOE_SOURCE" ] && [ -d "$HOME/.mimoe" ] && [ -f "$HOME/.mimoe/mimoe.lic" ]; then
    MIMOE_SOURCE="$HOME/.mimoe"
  fi

  if [ -n "$MIMOE_SOURCE" ]; then
    # ── Copy from local installation ──────────────────────────────────────
    echo "[3/4] Copying mimOE runtime from $MIMOE_SOURCE..."

    # Find binary — could be at bin/mimoe (v3.22.0+) or top-level mimoe (v3.20.2)
    MIMOE_BIN=""
    if [ -f "$MIMOE_SOURCE/bin/mimoe" ]; then
      MIMOE_BIN="$MIMOE_SOURCE/bin/mimoe"
    elif [ -f "$MIMOE_SOURCE/mimoe" ]; then
      MIMOE_BIN="$MIMOE_SOURCE/mimoe"
    fi

    if [ -z "$MIMOE_BIN" ]; then
      echo "  ERROR: mimOE binary not found in $MIMOE_SOURCE"
      echo "  Expected bin/mimoe or mimoe at top level."
      exit 1
    fi

    # Find license — *.lic
    MIMOE_LIC=$(find "$MIMOE_SOURCE" -maxdepth 1 -name '*.lic' -print -quit 2>/dev/null || true)
    if [ -z "$MIMOE_LIC" ]; then
      echo "  ERROR: No .lic file found in $MIMOE_SOURCE"
      exit 1
    fi

    mkdir -p "$MIMOE_DEST/bin" "$MIMOE_DEST/addon"

    cp "$MIMOE_BIN" "$MIMOE_DEST/bin/mimoe"
    chmod +x "$MIMOE_DEST/bin/mimoe"
    echo "  Copied bin/mimoe"

    cp "$MIMOE_LIC" "$MIMOE_DEST/mimoe.lic"
    echo "  Copied mimoe.lic (from $(basename "$MIMOE_LIC"))"

    # API key env
    if [ -f "$MIMOE_SOURCE/mimoe-api-key.env" ]; then
      cp "$MIMOE_SOURCE/mimoe-api-key.env" "$MIMOE_DEST/mimoe-api-key.env"
      echo "  Copied mimoe-api-key.env"
    fi

    # Addons
    if [ -d "$MIMOE_SOURCE/addon" ]; then
      cp -R "$MIMOE_SOURCE/addon/"* "$MIMOE_DEST/addon/" 2>/dev/null || true
      ADDON_COUNT=$(ls "$MIMOE_DEST/addon" 2>/dev/null | { grep -v '.DS_Store' || true; } | wc -l | tr -d ' ')
      echo "  Copied addon/ ($ADDON_COUNT items)"
    fi

    # Symlink .edge if source has one
    if [ -d "$MIMOE_SOURCE/.edge" ]; then
      if [ -L "$MIMOE_DEST/.edge" ]; then
        rm "$MIMOE_DEST/.edge"
      elif [ -d "$MIMOE_DEST/.edge" ]; then
        rm -rf "$MIMOE_DEST/.edge"
      fi
      ln -s "$MIMOE_SOURCE/.edge" "$MIMOE_DEST/.edge"
      echo "  Symlinked .edge -> $MIMOE_SOURCE/.edge"
    fi

  else
    # ── Download from GitHub ──────────────────────────────────────────────
    echo "[3/4] Downloading mimOE ${MIMOE_VERSION} from GitHub..."

    # Detect platform
    OS=$(uname -s)
    ARCH=$(uname -m)

    case "$OS" in
      Darwin)
        case "$ARCH" in
          arm64) ASSET_PATTERN="macOS-developer-ARM64" ; EXT="zip" ;;
          x86_64) ASSET_PATTERN="macOS-developer-ARM64" ; EXT="zip"
            echo "  Note: No x86_64 macOS build available. Using ARM64 (works via Rosetta)." ;;
          *) echo "  ERROR: Unsupported macOS architecture: $ARCH"; exit 1 ;;
        esac ;;
      Linux)
        case "$ARCH" in
          aarch64|arm64) ASSET_PATTERN="linux-developer-ARM64-v" ; EXT="tar" ;;
          x86_64) ASSET_PATTERN="linux-developer-X86_64" ; EXT="tar" ;;
          *) echo "  ERROR: Unsupported Linux architecture: $ARCH"; exit 1 ;;
        esac ;;
      *) echo "  ERROR: Unsupported OS: $OS (supported: macOS, Linux)"; exit 1 ;;
    esac

    # Build download URL
    RELEASE_URL="https://api.github.com/repos/${MIMOE_REPO}/releases/tags/${MIMOE_VERSION}"
    echo "  Querying release: $MIMOE_VERSION"

    ASSET_URL=$(curl -sf "$RELEASE_URL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    name = asset['name']
    if '${ASSET_PATTERN}' in name and name.endswith('.${EXT}'):
        print(asset['browser_download_url'])
        sys.exit(0)
sys.exit(1)
" 2>/dev/null) || true

    if [ -z "$ASSET_URL" ]; then
      echo "  ERROR: Could not find a matching release asset for $OS/$ARCH"
      echo "  Looked for pattern: $ASSET_PATTERN (.$EXT)"
      echo "  Check: https://github.com/${MIMOE_REPO}/releases/tag/${MIMOE_VERSION}"
      exit 1
    fi

    ASSET_NAME=$(basename "$ASSET_URL")
    echo "  Downloading: $ASSET_NAME"

    TMPDIR_DL=$(mktemp -d)
    trap "rm -rf '$TMPDIR_DL'" EXIT

    curl -fSL -o "$TMPDIR_DL/$ASSET_NAME" "$ASSET_URL"
    echo "  Downloaded to temp dir"

    # Extract
    EXTRACT_DIR="$TMPDIR_DL/extracted"
    mkdir -p "$EXTRACT_DIR"

    if [ "$EXT" = "zip" ]; then
      unzip -q "$TMPDIR_DL/$ASSET_NAME" -d "$EXTRACT_DIR"
    else
      tar xf "$TMPDIR_DL/$ASSET_NAME" -C "$EXTRACT_DIR"
    fi
    echo "  Extracted"

    # Find binary
    MIMOE_BIN=$(find "$EXTRACT_DIR" -type f -name 'mimoe' -print -quit 2>/dev/null || true)
    if [ -z "$MIMOE_BIN" ]; then
      MIMOE_BIN=$(find "$EXTRACT_DIR" -type f -name 'mimoe*' ! -name '*.lic' ! -name '*.addon' ! -name '*.ini' -print -quit 2>/dev/null || true)
    fi

    if [ -z "$MIMOE_BIN" ]; then
      echo "  ERROR: Could not find mimoe binary in extracted archive"
      echo "  Contents:"
      find "$EXTRACT_DIR" -type f | head -20
      exit 1
    fi

    # Find license
    MIMOE_LIC=$(find "$EXTRACT_DIR" -type f -name '*.lic' -print -quit 2>/dev/null || true)
    if [ -z "$MIMOE_LIC" ]; then
      echo "  ERROR: Could not find license file (*.lic) in extracted archive"
      exit 1
    fi

    # Install to .mimoe/
    mkdir -p "$MIMOE_DEST/bin" "$MIMOE_DEST/addon"

    cp "$MIMOE_BIN" "$MIMOE_DEST/bin/mimoe"
    chmod +x "$MIMOE_DEST/bin/mimoe"
    echo "  Installed bin/mimoe"

    cp "$MIMOE_LIC" "$MIMOE_DEST/mimoe.lic"
    echo "  Installed mimoe.lic (from $(basename "$MIMOE_LIC"))"

    # Copy addons if present in archive
    ADDON_DIR=$(find "$EXTRACT_DIR" -type d -name 'addon' -print -quit 2>/dev/null || true)
    if [ -n "$ADDON_DIR" ]; then
      cp -R "$ADDON_DIR/"* "$MIMOE_DEST/addon/" 2>/dev/null || true
      ADDON_COUNT=$(ls "$MIMOE_DEST/addon" 2>/dev/null | { grep -v '.DS_Store' || true; } | wc -l | tr -d ' ')
      echo "  Installed addon/ ($ADDON_COUNT items)"
    fi

    # Generate API keys
    cat > "$MIMOE_DEST/mimoe-api-key.env" <<'APIEOF'
ACCOUNT_API_KEY=dev-account-api-key
MCM_API_KEY=dev-mcm-api-key
APIEOF
    echo "  Generated mimoe-api-key.env (dev defaults)"

    # Clean up temp
    rm -rf "$TMPDIR_DL"
    trap - EXIT

    echo "  mimOE ${MIMOE_VERSION} installed from GitHub release"
  fi

  echo ""
fi

# ── Step 4: Ensure API keys exist ─────────────────────────────────────────────

echo "[4/4] Checking API keys..."

if [ -f "$MIMOE_DEST/mimoe-api-key.env" ]; then
  echo "  OK: mimoe-api-key.env exists"
else
  cat > "$MIMOE_DEST/mimoe-api-key.env" <<'APIEOF'
ACCOUNT_API_KEY=dev-account-api-key
MCM_API_KEY=dev-mcm-api-key
APIEOF
  echo "  Generated mimoe-api-key.env (dev defaults)"
  echo "  mimOE will regenerate real keys on first start."
fi

echo ""

# ── Verify ───────────────────────────────────────────────────────────────────

echo "=== Verification ==="

ERRORS=0

if [ ! -d "$PROJECT_DIR/node_modules" ]; then
  echo "  FAIL: node_modules/ missing"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: node_modules/"
fi

if [ ! -d "$PROJECT_DIR/build" ]; then
  echo "  FAIL: build/ missing (webpack build failed)"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: build/"
fi

DEPLOY_TAR=$(find "$PROJECT_DIR/deploy" -name '*.tar' 2>/dev/null | head -1)
if [ -z "$DEPLOY_TAR" ]; then
  echo "  FAIL: deploy/*.tar missing (packaging failed)"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: deploy/$(basename "$DEPLOY_TAR")"
fi

if [ ! -x "$MIMOE_DEST/bin/mimoe" ]; then
  echo "  FAIL: .mimoe/bin/mimoe missing or not executable"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: .mimoe/bin/mimoe"
fi

if [ ! -f "$MIMOE_DEST/mimoe.lic" ]; then
  echo "  FAIL: .mimoe/mimoe.lic missing"
  ERRORS=$((ERRORS + 1))
else
  echo "  OK: .mimoe/mimoe.lic"
fi

if [ -f "$MIMOE_DEST/mimoe-api-key.env" ]; then
  echo "  OK: .mimoe/mimoe-api-key.env"
else
  echo "  WARN: .mimoe/mimoe-api-key.env missing"
fi

if [ -L "$MIMOE_DEST/.edge" ]; then
  echo "  OK: .mimoe/.edge -> $(readlink "$MIMOE_DEST/.edge")"
elif [ -d "$MIMOE_DEST/.edge" ]; then
  echo "  OK: .mimoe/.edge (local)"
else
  echo "  INFO: .mimoe/.edge will be created on first mimOE start"
fi

ADDON_COUNT=$(ls "$MIMOE_DEST/addon" 2>/dev/null | { grep -v '.DS_Store' || true; } | wc -l | tr -d ' ')
if [ "$ADDON_COUNT" -gt 0 ]; then
  echo "  OK: .mimoe/addon/ ($ADDON_COUNT items)"
else
  echo "  WARN: .mimoe/addon/ is empty (mesh-foundation may be needed)"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "Init completed with $ERRORS error(s). Check output above."
  exit 1
else
  echo "Init complete. Start mimOE with:"
  echo ""
  echo "  ./scripts/start-mimoe.sh"
  echo ""
  echo "Then deploy with:"
  echo ""
  echo "  ./scripts/deploy.sh"
fi
