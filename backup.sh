#!/usr/bin/env bash
set -euo pipefail

ROOT=/opt/homelab
BACKUP_ROOT=/opt/backups/homelab
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DUMP_DIR="$BACKUP_ROOT/$DATE/db"
mkdir -p "$DUMP_DIR"
cd "$ROOT"

# Load server-side environment.
set -a
source "$ROOT/.env"
set +a

# Database dumps: logical backups are portable and safer than copying live DB files.
echo "==> Immich PostgreSQL"
docker compose exec -T immich-db pg_dump -U postgres -d immich | gzip > "$DUMP_DIR/immich.sql.gz"

echo "==> Docmost PostgreSQL"
docker compose exec -T docmost-db pg_dump -U docmost -d docmost | gzip > "$DUMP_DIR/docmost.sql.gz"

echo "==> n8n PostgreSQL"
docker compose exec -T n8n-postgres pg_dump -U n8n -d n8n | gzip > "$DUMP_DIR/n8n.sql.gz"

echo "==> Mealie PostgreSQL"
docker compose exec -T mealie-postgres pg_dump -U mealie -d mealie | gzip > "$DUMP_DIR/mealie.sql.gz"

echo "==> Vikunja MariaDB"
docker compose exec -T vikunja-mariadb sh -c \
  'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction vikunja' \
  | gzip > "$DUMP_DIR/vikunja.sql.gz"

echo "==> Zulip PostgreSQL"
docker compose exec -T zulip-db pg_dump -U zulip -d zulip | gzip > "$DUMP_DIR/zulip.sql.gz"

# Zulip uses named volumes, so archive them explicitly.
for volume in zulip_data zulip_postgresql zulip_rabbitmq zulip_redis; do
  echo "==> Zulip volume: $volume"
  docker run --rm \
    -v "${volume}:/data:ro" \
    -v "$DUMP_DIR:/backup" \
    alpine:3.20 \
    tar czf "/backup/${volume}.tgz" -C /data .
done

# Restic repository must be off-host for disaster recovery.
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:?Set RESTIC_REPOSITORY}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:?Set RESTIC_PASSWORD_FILE}"

echo "==> Restic backup"
restic backup \
  /home/rahul/immich \
  /home/rahul/jellyfin \
  /home/rahul/paperless \
  /home/rahul/homepage \
  /home/rahul/docmost \
  /home/rahul/metube \
  /home/rahul/n8n \
  /home/rahul/mealie \
  /home/rahul/qbittorrent \
  /home/rahul/vikunja \
  "$DUMP_DIR" \
  /opt/homelab \
  --exclude '/home/rahul/immich/pg_data' \
  --exclude '/home/rahul/docmost/db' \
  --exclude '/home/rahul/n8n/postgres_data' \
  --exclude '/home/rahul/mealie/postgres' \
  --exclude '/home/rahul/vikunja/mariadb_data'

restic forget --keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune

echo "==> Backup completed: $DATE"
