# Disaster Recovery Runbook

The goal is to rebuild the host without relying on Docker's existing state.

## 1. New server

Install:
- Ubuntu/Debian
- Docker Engine + Compose plugin
- Git
- Restic

Clone the repository to `/opt/homelab`.

## 2. Restore secrets

Restore `/opt/homelab/.env` from the protected secret store/password manager.

Do **not** regenerate encryption keys for existing applications. Existing n8n and Vikunja data may depend on their original keys.

## 3. Restore files

Use Restic to restore the desired snapshot.

Example:

```bash
export RESTIC_REPOSITORY=...
export RESTIC_PASSWORD_FILE=/root/.config/restic/password
restic snapshots
restic restore <SNAPSHOT_ID> --target /
```

Restore `/home/rahul/...` and `/opt/homelab` before starting applications.

## 4. Restore databases

Start only the required database services:

```bash
docker compose up -d immich-db docmost-db n8n-postgres mealie-postgres vikunja-mariadb zulip-db
```

Wait until they are ready, then restore the corresponding logical dumps.

PostgreSQL example:

```bash
gunzip -c immich.sql.gz | docker compose exec -T immich-db psql -U postgres -d immich
```

Repeat for Docmost, n8n, Mealie and Zulip.

MariaDB example:

```bash
gunzip -c vikunja.sql.gz | docker compose exec -T vikunja-mariadb \
  mariadb -u root -p"$VIKUNJA_DB_ROOT_PASSWORD" vikunja
```

For a production recovery, test these commands on a disposable restore host before relying on them.

## 5. Restore Zulip named volumes

Stop Zulip first.

```bash
docker compose down
```

Recreate the volumes and extract each archive into its corresponding volume. Do not overwrite a live volume while a service is running.

## 6. Start the full stack

```bash
docker compose up -d
docker compose ps
```

## 7. Nextcloud

Nextcloud AIO is intentionally restored through its AIO backup/recovery process rather than treating its master container as an ordinary application volume. The Compose file only recreates the AIO master container.

## 8. Recovery test

A backup is not considered valid until you have successfully performed a restore test.

Recommended cadence:
- daily automated backups
- weekly verification
- monthly restore drill
- one off-site backup target
