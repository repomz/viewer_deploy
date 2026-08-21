#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

docker compose config --quiet
docker compose ps
if docker compose exec -T frontend test -r /etc/viewer-tls/fullchain.pem; then
  docker compose exec -T frontend wget -q --no-check-certificate -O - \
    https://127.0.0.1:8443/healthz
else
  docker compose exec -T frontend wget -q -O - http://127.0.0.1:8080/healthz
fi
docker compose exec -T backend wget -q -O /dev/null http://127.0.0.1:8080/
echo "Viewer Compose stack is healthy"
