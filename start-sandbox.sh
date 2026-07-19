#!/bin/bash
cd /Users/khangho/OrbStack-ELK
docker compose -f compose.sandbox.yml up -d
echo "Sandbox stack started."
