#!/bin/bash
cd ~/OrbStack-ELK
docker compose -f compose.elk.yml up -d
echo "Waiting for Elasticsearch..."
until curl -s http://localhost:9200 > /dev/null; do sleep 2; done
echo "ELK stack ready."
