#!/usr/bin/env bash
# Convert a Sigma rule and count hits in the recent detonation window (expect >=1)
# and the recorded baseline window (expect 0).
# Usage: detection-rules/validate.sh <rule.yml> [tp_window_minutes]
# Needs sigma-cli: pip install sigma-cli && sigma plugin install elasticsearch
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
set -a; . ./.env; set +a

RULE="${1:?usage: validate.sh <rule.yml> [tp_window_minutes]}"
TP_MIN="${2:-30}"
PIPE="detection-rules/pipelines/falco-ecs-sigma.yml"
INDEX="logs-*"
ES="http://localhost:${ES_PORT}"
AUTH="elastic:${ELASTIC_PASSWORD}"

command -v sigma >/dev/null || { echo "ERROR: sigma-cli not installed (pip install sigma-cli; sigma plugin install elasticsearch)"; exit 1; }

echo "==> Converting $RULE"
QUERY="$(sigma convert -t elasticsearch -f lucene -p "$PIPE" "$RULE" | tail -n 1)"
[ -z "$QUERY" ] && { echo "ERROR: empty query from conversion"; exit 1; }
echo "    query: $QUERY"

count() { # $1=gte $2=lte
  curl -s -u "$AUTH" -H 'Content-Type: application/json' "$ES/$INDEX/_count" -d "{
    \"query\":{\"bool\":{\"must\":[
      {\"query_string\":{\"query\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$QUERY")}},
      {\"range\":{\"@timestamp\":{\"gte\":\"$1\",\"lte\":\"$2\"}}}
    ]}}}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("count","?"))'
}

echo "==> True-positive window (last ${TP_MIN}m):"
TP="$(count "now-${TP_MIN}m" "now")"; echo "    hits: $TP"

FP="n/a"
if [ -f detection-rules/fixtures/baseline.env ]; then
  . detection-rules/fixtures/baseline.env
  echo "==> False-positive baseline window (${BASELINE_GTE} .. ${BASELINE_LTE}):"
  FP="$(count "$BASELINE_GTE" "$BASELINE_LTE")"; echo "    hits: $FP"
else
  echo "==> No baseline recorded (run scripts/baseline-capture.sh first) - skipping FP check."
fi

echo ""
echo "RESULT: TP=$TP FP=$FP"
rc=0
if [ "$TP" != "0" ] && [ "$TP" != "?" ]; then
  echo "  [PASS] rule fires on malicious activity"
else
  echo "  [FAIL] rule did not fire - detonate the sample or widen the window"
  rc=1
fi
if [ "$FP" = "0" ]; then
  echo "  [PASS] no false positives in baseline"
elif [ "$FP" != "n/a" ]; then
  echo "  [FAIL] rule fired $FP times on the clean baseline (noisy)"
  rc=1
fi
exit "$rc"
