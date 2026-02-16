#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TraceDeck"
BUNDLE_ID="swair.tracedeck"
PROJECT_PATH="TraceDeck.xcodeproj"
SCHEME="TraceDeck"
DERIVED_DATA_PATH="build"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"

AGENT_BINARY="activity-agent/dist/activity-agent"
AGENT_EXTENSION="activity-agent/dist/extension-bundle.js"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== TraceDeck Build & Run ===${NC}"

# Kill existing instance
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -f "$APP_NAME.app" 2>/dev/null || true
# Also kill legacy app name to avoid stale permission prompts from old builds.
pkill -x "ctxl" 2>/dev/null || true
pkill -f "ctxl.app" 2>/dev/null || true

# Build activity-agent artifacts if missing
if [ ! -f "$AGENT_BINARY" ] || [ ! -f "$AGENT_EXTENSION" ]; then
    echo -e "${YELLOW}Building activity-agent artifacts...${NC}"
    if [ ! -d "activity-agent/node_modules" ]; then
        (cd activity-agent && npm install --silent)
    fi
    (cd activity-agent && npm run build:binary && npm run build:extension)
fi

# Build the app
echo -e "${YELLOW}Building...${NC}"
xcodebuild -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build 2>&1 | grep -E "^(Build|error:|warning:|\\*\\*)" || true

# Check build succeeded
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

# Optional permission reset:
# RESET_PERMISSIONS=1 ./run.sh
if [ "${RESET_PERMISSIONS:-0}" = "1" ]; then
    echo -e "${YELLOW}Resetting macOS permissions for ${BUNDLE_ID}...${NC}"
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
fi

echo ""
echo -e "${YELLOW}If capture/hotkeys fail, verify permissions:${NC}"
echo -e "  1. System Settings -> Privacy & Security -> Accessibility"
echo -e "  2. System Settings -> Privacy & Security -> Screen & System Audio Recording"
echo -e "  3. System Settings -> Privacy & Security -> Microphone"
echo ""

read -p "Open Privacy & Security settings now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "x-apple.systempreferences:com.apple.preference.security"
fi

echo -e "${GREEN}Launching ${APP_NAME}...${NC}"
open "$APP_PATH"
echo -e "${GREEN}Done.${NC} (${APP_PATH})"
