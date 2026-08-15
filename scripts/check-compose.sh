#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

docker compose config --quiet
docker compose ps
docker compose exec -T frontend wget -q -O - http://127.0.0.1:8080/healthz
docker compose exec -T backend wget -q -O /dev/null http://127.0.0.1:8080/
echo "Viewer Compose stack is healthy"

