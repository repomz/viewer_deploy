#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
backup_root=${1:-"$project_dir/backups/$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$backup_root"

cd "$project_dir"
docker compose exec -T postgres sh -ec \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$backup_root/postgres.dump"

for volume in orthanc-data reports-data plans-data xa-cache-data; do
  docker run --rm \
    -v "viewer_${volume}:/source:ro" \
    -v "$backup_root:/backup" \
    alpine:3.22 \
    tar -C /source -czf "/backup/${volume}.tar.gz" .
done

echo "Backup written to $backup_root"
