# Homelab Infrastructure

Single Docker Compose deployment for **Nextcloud AIO**, **Vikunja**, **n8n**, and **Vaultwarden** (Bitwarden-compatible Password Manager).

## Design

- **Git repository = desired state**: Docker Compose file, backup/deploy scripts, and documentation.
- **`/opt/homelab/.env`**: Secret configuration file (never committed).
- **Docker Named Volumes**: All persistent data is stored in isolated Docker named volumes (`n8n_data`, `n8n_db_data`, `vikunja_files`, `vikunja_db_data`, `nextcloud_aio_mastercontainer`, `vaultwarden_data`) without host-path dependencies.
- **Out-of-the-box Deployment**: Cloned repo + `.env` file works on any Docker host without pre-creating host directories.

## Deployment

```bash
sudo mkdir -p /opt/homelab
sudo chown "$USER":"$USER" /opt/homelab
git clone <YOUR_REPO> /opt/homelab
cd /opt/homelab
cp .env.example .env
chmod 600 .env
nano .env

docker compose config
docker compose pull
docker compose up -d
docker compose ps
```

## Service Port Mapping

- **Nextcloud AIO**: Port `8080`
- **Vikunja**: Port `3456`
- **n8n**: Port `5678`
- **Vaultwarden**: Port `8088`

## Backup & Restoration

- **Nextcloud AIO (Built-in BorgBackup)**:
  - Managed via Nextcloud AIO Web Interface (`https://<YOUR_SERVER_IP>:8080`).
  - Safely stops child containers, performs an encrypted/deduplicated Borg snapshot of database & files, and restarts containers automatically.
- **n8n, Vikunja & Vaultwarden (`backup.sh`)**:
  - Dumps PostgreSQL (`n8n-postgres`) & MariaDB (`vikunja-mariadb`).
  - Archives persistent Docker named volumes (`n8n_data`, `n8n_db_data`, `vikunja_files`, `vikunja_db_data`, `vaultwarden_data`, `nextcloud_aio_mastercontainer`) into portable tarballs (`$BACKUP_ROOT/$DATE/volumes/*.tgz`).
  - Supports optional off-host sync using Restic (`RESTIC_REPOSITORY`).
- **Restoration**:
  - Deploy the stack on any host using `docker-compose up -d`.
  - Extract volume archives or restore database dumps for n8n, Vikunja, and Vaultwarden.
  - Nextcloud AIO is restored via the AIO Web Interface using your BorgBackup passphrase & archive path.




