#!/usr/bin/env bash
set -euo pipefail

ROOT=/opt/homelab
BACKUP_ROOT=/opt/backups/homelab
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DUMP_DIR="$BACKUP_ROOT/$DATE/db"
VOL_DIR="$BACKUP_ROOT/$DATE/volumes"
mkdir -p "$DUMP_DIR" "$VOL_DIR"
cd "$ROOT"

# Load server-side environment if available.
if [ -f "$ROOT/.env" ]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

# Database dumps: logical backups for database containers
echo "==> Backing up databases (logical dumps)"

echo "--> n8n PostgreSQL"
docker compose exec -T n8n-postgres pg_dump -U n8n -d n8n | gzip > "$DUMP_DIR/n8n.sql.gz"

echo "--> Vikunja MariaDB"
docker compose exec -T vikunja-mariadb sh -c \
  'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction vikunja' \
  | gzip > "$DUMP_DIR/vikunja.sql.gz"

# Persistent Docker volume archives
echo "==> Backing up Docker persistent named volumes"
VOLUMES=(
  "n8n_data"
  "n8n_db_data"
  "vikunja_files"
  "vikunja_db_data"
  "nextcloud_aio_mastercontainer"
)

# Resolve project volume name prefix
COMPOSE_PROJECT_NAME=$(docker compose config --format json 2>/dev/null | grep -o '"name":"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "homelab")

for vol in "${VOLUMES[@]}"; do
  FULL_VOL_NAME="${COMPOSE_PROJECT_NAME}_${vol}"
  if ! docker volume inspect "$FULL_VOL_NAME" >/dev/null 2>&1; then
    FULL_VOL_NAME="$vol"
  fi
  
  if docker volume inspect "$FULL_VOL_NAME" >/dev/null 2>&1; then
    echo "--> Archiving volume: $FULL_VOL_NAME"
    docker run --rm \
      -v "${FULL_VOL_NAME}:/volume_data:ro" \
      -v "$VOL_DIR:/backup" \
      alpine:3.20 \
      tar czf "/backup/${vol}.tgz" -C /volume_data .
  else
    echo "--> Warning: Volume $FULL_VOL_NAME not found, skipping."
  fi
done

# Off-host Restic backup if configured
if [ -n "${RESTIC_REPOSITORY:-}" ] && [ -n "${RESTIC_PASSWORD_FILE:-}" ]; then
  echo "==> Restic backup (off-host)"
  restic backup \
    "$DUMP_DIR" \
    "$VOL_DIR" \
    "$ROOT"

  restic forget --keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
fi

echo "==> Backup completed successfully: $DATE"




