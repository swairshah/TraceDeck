#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TraceDeck"
BUNDLE_ID="swair.tracedeck"
LEGACY_BUNDLE_IDS=("swair.ctxl" "com.swair.monitome")
LEGACY_PROCESS_NAMES=("ctxl" "Monitome")
PROJECT_PATH="TraceDeck.xcodeproj"
SCHEME="TraceDeck"
DERIVED_DATA_PATH="build"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"

AGENT_SCRIPT="activity-agent/dist/activity-agent.js"
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
# Also kill legacy app names to avoid stale permission prompts from old builds.
for legacy_name in "${LEGACY_PROCESS_NAMES[@]}"; do
    pkill -x "$legacy_name" 2>/dev/null || true
    pkill -f "$legacy_name.app" 2>/dev/null || true
done

# Build activity-agent artifacts if missing
if [ ! -f "$AGENT_SCRIPT" ] || [ ! -f "$AGENT_EXTENSION" ]; then
    echo -e "${YELLOW}Building activity-agent artifacts...${NC}"
    if [ ! -d "activity-agent/node_modules" ]; then
        (cd activity-agent && npm install --silent)
    fi
    (cd activity-agent && npm run build:bundle && npm run build:extension)
fi

# Build the app
echo -e "${YELLOW}Building...${NC}"
set +e
BUILD_OUTPUT="$(
    xcodebuild -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        build 2>&1
)"
BUILD_STATUS=$?
set -e
echo "$BUILD_OUTPUT" | grep -E "^(Build|error:|warning:|\\*\\*)" || true

# Check build succeeded
APP_EXEC="$APP_PATH/Contents/MacOS/$APP_NAME"
if [ $BUILD_STATUS -ne 0 ] || [ ! -x "$APP_EXEC" ]; then
    echo -e "${RED}Build failed!${NC}"
    if [ $BUILD_STATUS -ne 0 ]; then
        echo "$BUILD_OUTPUT" | tail -n 40
    fi
    echo "Expected executable not found: $APP_EXEC"
    exit 1
fi

# Permission handling for current + legacy TraceDeck bundle IDs:
# - Always reset Accessibility for current + legacy bundle IDs to clear stale signatures
# - Optional full reset for Microphone/ScreenCapture if needed:
#   RESET_ALL_PERMISSIONS=1 ./run.sh
echo -e "${YELLOW}Resetting Accessibility permission entries...${NC}"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
for legacy_id in "${LEGACY_BUNDLE_IDS[@]}"; do
    tccutil reset Accessibility "$legacy_id" 2>/dev/null || true
done

if [ "${RESET_ALL_PERMISSIONS:-0}" = "1" ]; then
    echo -e "${YELLOW}Resetting Microphone and ScreenCapture entries...${NC}"
    tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
    for legacy_id in "${LEGACY_BUNDLE_IDS[@]}"; do
        tccutil reset Microphone "$legacy_id" 2>/dev/null || true
        tccutil reset ScreenCapture "$legacy_id" 2>/dev/null || true
    done
fi

echo ""
echo -e "${YELLOW}After rebuilds, re-grant permissions to this exact app path if needed:${NC}"
echo -e "  ${GREEN}$(pwd)/$APP_PATH${NC}"
echo -e ""
echo -e "${YELLOW}Required pages:${NC}"
echo -e "  1. Accessibility"
echo -e "  2. Screen & System Audio Recording"
echo -e "  3. Microphone"
echo ""

read -p "Open permission settings now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    echo -e "${YELLOW}After updating permissions, press Enter to launch ${APP_NAME}...${NC}"
    read
fi

echo -e "${GREEN}Launching ${APP_NAME}...${NC}"
open "$APP_PATH"
echo -e "${GREEN}Done.${NC} (${APP_PATH})"
