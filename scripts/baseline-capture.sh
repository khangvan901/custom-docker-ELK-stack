#!/usr/bin/env bash
# Record a "clean" time window (no malware detonated) as a fixture. validate.sh
# uses it as the false-positive baseline: any rule that fires in this window is
# noisy. Keep the sandbox idle while this runs.
#
# Usage: scripts/baseline-capture.sh [DURATION_SECONDS]   (default 120)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${1:-120}"
OUT="$REPO_DIR/detection-rules/fixtures/baseline.env"
mkdir -p "$(dirname "$OUT")"

GTE="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
echo "==> Capturing a clean baseline for ${DURATION}s. Keep the sandbox IDLE (do not detonate anything)."
sleep "$DURATION"
LTE="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

cat > "$OUT" <<EOF
# Clean baseline window (UTC). Regenerate with scripts/baseline-capture.sh.
BASELINE_GTE=$GTE
BASELINE_LTE=$LTE
EOF
echo "==> Baseline saved to $OUT"
cat "$OUT"
