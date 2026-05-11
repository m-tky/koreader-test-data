#!/usr/bin/env bash
#
# test-vertical.sh — Automated vertical text screenshot tests for KOReader
#
# Runs KOReader emulator (headless) with a vertical text test EPUB,
# applies vertical-rl CSS via ReaderStyleTweak,
# takes screenshots at multiple pages, and optionally
# tests dictionary lookup coordinate conversion.
#
# IMPORTANT: Phase 1 uses simple_ja_noruby.epub (no ruby annotations).
#            それから.epub contains ruby and is for Phase 2+.
#
# Prerequisites:
#   - KOReader emulator built (SDL backend)
#   - busted installed for running specs
#   - Test EPUB at tests/fixtures/vertical_text/simple_ja_noruby.epub
#     (or set VERTICAL_TEST_EPUB to override)
#
# Usage:
#   ./test-vertical.sh              # Run all tests
#   ./test-vertical.sh screenshots  # Only screenshot tests
#   ./test-vertical.sh dict         # Only dictionary coordinate tests
#   ./test-vertical.sh compare      # Compare screenshots with baseline
#
# Output:
#   screenshots/vertical/ — generated screenshots
#   screenshots/baseline/ — baseline screenshots (for comparison)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KOREADER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EPUB_FILE="${VERTICAL_TEST_EPUB:-${KOREADER_ROOT}/base/tests/fixtures/vertical_text/simple_ja_noruby.epub}"
SCREENSHOT_DIR="${SCRIPT_DIR}/screenshots"
BASELINE_DIR="${SCREENSHOT_DIR}/baseline"
VERTICAL_DIR="${SCREENSHOT_DIR}/vertical"
TEST_SPEC="spec/front/unit/vertical_text_spec.lua"
# The emulator install dir has frontend/, common/, spec/ etc all together
EMU_DIR="${KOREADER_ROOT}/koreader-emulator-x86_64-unknown-linux-gnu-debug/koreader"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[test-vertical]${NC} $*"; }
warn() { echo -e "${YELLOW}[test-vertical]${NC} $*"; }
err() { echo -e "${RED}[test-vertical]${NC} $*" >&2; }

# ─── Checks ───────────────────────────────────────────────────────────

check_prereqs() {
    if [ ! -f "$EPUB_FILE" ]; then
        err "Test EPUB not found at: $EPUB_FILE"
        err "Phase 1 requires a Japanese EPUB without ruby annotations."
        exit 1
    fi

    if ! command -v busted &>/dev/null; then
        err "busted not found. Install it: luarocks install busted"
        exit 1
    fi

    # Check that the emulator can run (SDL + KOReader libs)
    if [ ! -f "${KOREADER_ROOT}/reader.lua" ]; then
        err "reader.lua not found — emulator not built?"
        exit 1
    fi
}

# ─── Setup ────────────────────────────────────────────────────────────

setup_dirs() {
    mkdir -p "$VERTICAL_DIR"
    mkdir -p "$BASELINE_DIR"
    log "Screenshot directory: $SCREENSHOT_DIR"
}

# ─── Run tests ────────────────────────────────────────────────────────

run_tests() {
    local filter="${1:-}"

    log "Running vertical text tests with $EPUB_FILE"

    # Set environment for headless SDL
    export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-dummy}"
    export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
    export LC_ALL="en_US.UTF-8"

    # Pass EPUB path to the spec via environment
    export VERTICAL_TEST_EPUB="$EPUB_FILE"
    export VERTICAL_TEST_SCREENSHOT_DIR="$VERTICAL_DIR"
    export VERTICAL_TEST_BASELINE_DIR="$BASELINE_DIR"

    local runtests_args=(--busted)
    if [ -n "$filter" ]; then
        runtests_args+=(--tags="$filter")
    fi

    # Run from emulator dir: has frontend/, common/, spec/ all together
    cd "$EMU_DIR/spec"
    ./runtests "${runtests_args[@]}" -- "$TEST_SPEC"
}

# ─── Compare screenshots ──────────────────────────────────────────────

compare_screenshots() {
    log "Comparing screenshots against baseline..."

    local pass=0
    local fail=0
    local missing=0

    for vertical_png in "$VERTICAL_DIR"/*.png; do
        [ -f "$vertical_png" ] || continue
        local basename
        basename="$(basename "$vertical_png")"
        local baseline_png="${BASELINE_DIR}/${basename}"

        if [ ! -f "$baseline_png" ]; then
            warn "  MISSING baseline: $basename"
            missing=$((missing + 1))
            continue
        fi

        # Use compare from ImageMagick if available, otherwise file-size check
        if command -v compare &>/dev/null; then
            local diff_val
            diff_val=$(compare -metric AE "$baseline_png" "$vertical_png" /dev/null 2>&1) || true
            if [ "$diff_val" = "0" ]; then
                log "  PASS: $basename"
                pass=$((pass + 1))
            else
                err "  FAIL: $basename (diff pixels: $diff_val)"
                fail=$((fail + 1))
            fi
        else
            # Fallback: compare file sizes (rough check)
            local size_base size_vert
            size_base=$(stat -c%s "$baseline_png" 2>/dev/null || stat -f%z "$baseline_png")
            size_vert=$(stat -c%s "$vertical_png" 2>/dev/null || stat -f%z "$vertical_png")
            if [ "$size_base" = "$size_vert" ]; then
                log "  PASS: $basename (size match)"
                pass=$((pass + 1))
            else
                err "  FAIL: $basename (size mismatch: $size_base vs $size_vert)"
                fail=$((fail + 1))
            fi
        fi
    done

    echo ""
    log "Results: ${pass} passed, ${fail} failed, ${missing} missing baseline"
    [ "$fail" -eq 0 ] || exit 1
}

# ─── Promote current screenshots to baseline ──────────────────────────

promote_baseline() {
    log "Promoting current screenshots to baseline..."
    cp "$VERTICAL_DIR"/*.png "$BASELINE_DIR"/ 2>/dev/null || true
    log "Done. $(ls -1 "$BASELINE_DIR"/*.png 2>/dev/null | wc -l) baselines set."
}

# ─── Main ─────────────────────────────────────────────────────────────

case "${1:-run}" in
    run|test|"")
        check_prereqs
        setup_dirs
        run_tests "${2:-}"
        ;;
    screenshots)
        check_prereqs
        setup_dirs
        run_tests "screenshot"
        ;;
    dict|dictionary)
        check_prereqs
        setup_dirs
        run_tests "dict"
        ;;
    compare)
        compare_screenshots
        ;;
    baseline|promote)
        promote_baseline
        ;;
    *)
        echo "Usage: $0 {run|screenshots|dict|compare|baseline}"
        echo "Set VERTICAL_TEST_EPUB to override default test EPUB."
        echo "Phase 1 default: tests/fixtures/vertical_text/simple_ja_noruby.epub (no ruby)"
        exit 1
        ;;
esac
