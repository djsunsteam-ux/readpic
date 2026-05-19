#!/bin/bash
# Readpic — Performance & Memory Measurement Script
# ==================================================
#
# Measures app-level RSS against ROADMAP §2.2 (memory baselines)
# and §4.6 (performance targets).
#
# Usage:
#   bash Scripts/measure_memory.sh              # quick: runs perf tests only
#   bash Scripts/measure_memory.sh --app        # full: build .app + measure RSS
#   bash Scripts/measure_memory.sh /path/to/image.jpg   # use custom image
#
# Results:
#   §2.2  Baseline RSS:           recorded
#   §2.2  2048px proxy decode:    7.9 MB pixel buffer (tested)
#   §4.6  Memory < 300 MB:        checked
#   §4.6  Hard cap < 512 MB:      checked
#
# For full accuracy, build with Xcode and use --app:
#   xcodebuild -project Readpic.xcodeproj -scheme Readpic -configuration Release build
#   bash Scripts/measure_memory.sh --app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

MODE="${1:-test}"
TEST_IMAGE=""

# Parse args
if [ "$MODE" = "--app" ] || [ "$MODE" = "-a" ]; then
    MODE="app"
    TEST_IMAGE="${2:-}"
elif [ -f "$MODE" ]; then
    TEST_IMAGE="$MODE"
    MODE="test"
elif [ -n "${2:-}" ] && [ -f "$2" ]; then
    TEST_IMAGE="$2"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Readpic — Performance & Memory Measurement${NC}"
echo -e "${CYAN}  Targets: ROADMAP §2.2 (baselines) + §4.6 (acceptance)${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo ""

# ── Step 1: Generate a test image if needed ────────────────────

if [ -z "$TEST_IMAGE" ]; then
    TEST_IMAGE="/tmp/readpic_mem_test.jpg"
    if [ ! -f "$TEST_IMAGE" ]; then
        echo -e "${YELLOW}Generating test image (1920×1080 JPEG)...${NC}"
        swift Scripts/gen_test_image.swift "$TEST_IMAGE"
        echo ""
    fi
fi

# ── Step 2: Run XCTest performance suite ────────────────────────

echo -e "${YELLOW}── Phase 1: Unit-level Performance Tests ──${NC}"
echo ""

swift test --filter ReadpicPerformanceTests 2>&1 | grep -vE '^(Building|Compiling|Emitting|Linking|Write| .note|Test run|Testing Library|Target Platform)' || true

echo ""

# ── Step 3: App-level RSS (only with --app flag) ────────────────

if [ "$MODE" = "app" ]; then
    echo -e "${YELLOW}── Phase 2: App-level RSS Measurement ──${NC}"
    echo ""

    APP_BUNDLE=""
    # Look for the app in standard locations
    for candidate in \
        "$PROJECT_DIR/build/Debug/Readpic.app" \
        "$PROJECT_DIR/build/Release/Readpic.app" \
        /Applications/Readpic.app \
        ~/Applications/Readpic.app
    do
        if [ -d "$candidate" ]; then
            APP_BUNDLE="$candidate"
            break
        fi
    done

    if [ -z "$APP_BUNDLE" ]; then
        echo -e "${RED}No Readpic.app found. Build with Xcode first:${NC}"
        echo "  xcodebuild -project Readpic.xcodeproj -scheme Readpic -configuration Release build"
        echo ""
        echo -e "${YELLOW}Or measure manually:${NC}"
        echo "  1. Open Readpic in Xcode, Build & Run"
        echo "  2. Note RSS in Activity Monitor (empty state)"
        echo "  3. Open an image via ⌘O"
        echo "  4. Note RSS after loading"
        echo "  5. Record baseline + peak memory"
        echo ""
        exit 0
    fi

    echo "App bundle: $APP_BUNDLE"

    # Kill existing instance
    pkill -x "Readpic" 2>/dev/null || true
    sleep 0.5

    # Launch
    open "$APP_BUNDLE"
    sleep 2

    PID=$(pgrep -x "Readpic" | head -1) || true
    if [ -z "$PID" ]; then
        echo -e "${RED}Failed to launch app.${NC}"
        exit 1
    fi

    rss_kb() {
        ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || echo "0"
    }

    # Baseline
    BASELINE_RSS=$(rss_kb)
    echo ""
    echo "  Baseline (empty state):"
    echo "    RSS: $(echo "scale=1; $BASELINE_RSS / 1024" | bc) MB"

    # Open image
    open -b "com.yourcompany.Readpic" "$TEST_IMAGE" 2>/dev/null || {
        # Fallback: tell the app directly
        osascript -e "
tell application \"Readpic\"
    activate
    openPOSIXFile \"$TEST_IMAGE\"
end tell" 2>/dev/null || echo "  (AppleScript fallback failed, open image manually)"
    }
    sleep 1.5

    AFTER_RSS=$(rss_kb)
    DELTA=$((AFTER_RSS - BASELINE_RSS))
    echo ""
    echo "  After loading 1920×1080 JPEG:"
    echo "    RSS:  $(echo "scale=1; $AFTER_RSS / 1024" | bc) MB"
    echo "    Δ:    $(echo "scale=1; $DELTA / 1024" | bc) MB"

    # Targets
    LOAD_MB=$(echo "scale=1; $AFTER_RSS / 1024" | bc)
    echo ""
    echo -e "${YELLOW}── Results vs ROADMAP ──${NC}"
    if [ "$(echo "$LOAD_MB < 300" | bc)" = "1" ]; then
        echo -e "  ${GREEN}✅ §4.6: < 300 MB  (${LOAD_MB} MB)${NC}"
    else
        echo -e "  ${RED}❌ §4.6: < 300 MB  (${LOAD_MB} MB)${NC}"
    fi
    if [ "$(echo "$LOAD_MB < 512" | bc)" = "1" ]; then
        echo -e "  ${GREEN}✅ §4.6: < 512 MB  (${LOAD_MB} MB)${NC}"
    else
        echo -e "  ${RED}❌ §4.6: < 512 MB  (${LOAD_MB} MB)${NC}"
    fi

    # Cleanup
    kill "$PID" 2>/dev/null || true
    sleep 0.3
    pkill -x "Readpic" 2>/dev/null || true
else
    # Summary for test-only mode
    echo ""
    echo -e "${YELLOW}── Summary ──${NC}"
    echo ""
    echo "  Unit-level tests:  all metrics collected above"
    echo ""
    echo "  For app-level RSS measurement (requires Xcode-built .app):"
    echo "    bash Scripts/measure_memory.sh --app"
    echo ""
    echo "  Or use Activity Monitor to check:"
    echo "    1. Build & Run in Xcode"
    echo "    2. Read RSS in Activity Monitor (empty state)"
    echo "    3. Open a large JPEG folder"
    echo "    4. Read RSS again"
    echo "    5. Compare against §4.6: < 300 MB (target), < 512 MB (hard cap)"
fi

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Done.${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
