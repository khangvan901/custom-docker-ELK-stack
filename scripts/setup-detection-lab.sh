#!/usr/bin/env bash
# One-time enablement for the Sigma detection-engineering workflow:
#   - installs the falco-ecs ingest pipeline (parses Falco JSON -> ECS)
#   - attaches it to the logs-falco data stream via logs-falco@custom
#   - rolls the data stream over so new events are normalized
# Idempotent: safe to re-run.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
set -a; . ./.env; set +a
ES="http://localhost:${ES_PORT}"
AUTH="elastic:${ELASTIC_PASSWORD}"

echo "==> Installing ingest pipeline 'falco-ecs'..."
curl -s -u "$AUTH" -H 'Content-Type: application/json' \
  -X PUT "$ES/_ingest/pipeline/falco-ecs" \
  --data-binary @config/es/falco-ecs-pipeline.json | grep -q '"acknowledged":true' \
  && echo "    ok" || { echo "    FAILED"; exit 1; }

echo "==> Creating component template 'logs-falco@custom'..."
curl -s -u "$AUTH" -H 'Content-Type: application/json' \
  -X PUT "$ES/_component_template/logs-falco@custom" \
  --data-binary @config/es/logs-falco-custom.json | grep -q '"acknowledged":true' \
  && echo "    ok" || { echo "    FAILED"; exit 1; }

echo "==> Rolling over logs-falco-default so the pipeline takes effect..."
curl -s -u "$AUTH" -X POST "$ES/logs-falco-default/_rollover" | grep -q '"acknowledged":true' \
  && echo "    rolled over" || echo "    (rollover skipped/failed - new backing index may already exist)"

echo "==> Done. New Falco events will be parsed + ECS-normalized."
echo "    Verify with: detection-rules/validate.sh detection-rules/sigma/lin_fileless_memfd.yml"
