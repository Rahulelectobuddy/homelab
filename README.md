# Homelab Infrastructure

Single Docker Compose deployment for **Nextcloud AIO**, **Vikunja**, **Vaultwarden** (Bitwarden-compatible Password Manager), **Paperless-ngx** (Document Management System), and **SFTPGo** for Obsidian WebDAV sync.

## Design

- **Git repository = desired state**: Docker Compose file, backup/deploy scripts, and documentation.
- **`/opt/homelab/.env`**: Secret configuration for services (never committed).
- **Docker Named Volumes**: All persistent data is stored in isolated Docker named volumes (`vikunja_files`, `vikunja_db_data`, `nextcloud_aio_mastercontainer`, `vaultwarden_data`, `paperless_data`, `paperless_media`, `paperless_db_data`, `paperless_redis_data`, `sftpgo_data`, `sftpgo_config`) without host-path dependencies.
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
- **Vaultwarden**: Port `8088`
- **Paperless-ngx**: Port `8010` (customizable via `PAPERLESS_PORT`)
- **SFTPGo**: Admin `127.0.0.1:8089`, WebDAV `10080`, SFTP `2022`

## SFTPGo / Obsidian WebDAV setup

SFTPGo uses the official `drakkan/sftpgo:v2.7.6` image. Its two named volumes
persist across container recreation and normal `docker compose down` / `up`:

- `sftpgo_data` mounted at `/srv/sftpgo`: vault files under `data/<username>` and application backups.
- `sftpgo_config` mounted at `/var/lib/sftpgo`: SQLite database (users, admins, permissions), settings stored there, and SSH host keys.

Keep the same Compose project name/directory on redeployment so Docker reuses
these volumes. `docker compose down -v` deletes persistent data.
See the official [Docker storage documentation](https://github.com/sftpgo/docs/blob/main/docs/docker.md).

1. Start only the new service on your homelab host:

   ```bash
   cd /opt/homelab
   docker compose config --quiet
   docker compose pull sftpgo
   docker compose up -d sftpgo
   ```

2. The admin UI defaults to host loopback. From your computer, forward it:

   ```bash
   ssh -N -L 8089:127.0.0.1:8089 <SSH_USER>@<SERVER_IP>
   ```

   Open `http://localhost:8089/web/admin`, create the first administrator, then
   create a separate enabled user named `obsidian` with a strong password.
   Use **Local filesystem**, home directory `/srv/sftpgo/data/obsidian`, and grant
   list, download, upload, overwrite, create directories, rename, and delete
   permissions at `/`. Ensure WebDAV is allowed for this user. Do not add file
   filters that exclude dotfiles if you want to sync `.obsidian` settings.
   The admin account is separate from the WebDAV user.

3. In Obsidian, configure a WebDAV-capable plugin such as
   [Remotely Save](https://github.com/remotely-save/remotely-save) on each device:

   - Service: **WebDAV**.
   - Server URL: `http://<SERVER_IP>:10080/` on a trusted LAN, or your HTTPS WebDAV hostname below.
   - Username/password: the `obsidian` user credentials.
   - Remote folder: a distinct folder for each vault, using the same folder on every device for that vault.

   Run the plugin's connection check, sync one device first, then sync the others.
   Back up your vault before the first sync. Obsidian's official paid Sync service
   does not provide a WebDAV configuration; this setup uses a community plugin.
   CORS is enabled for Obsidian desktop/mobile origins with WebDAV methods allowed.

For remote access, use HTTPS through the host's existing Cloudflare Tunnel (or
another TLS reverse proxy). Route a hostname you control to
**`http://127.0.0.1:10080`**, and change the WebDAV port mapping in `compose.yml`
to `127.0.0.1:10080:10080` if all clients will use the tunnel. For example,
before the tunnel's catch-all rule:

```yaml
- hostname: <YOUR_WEBDAV_HOSTNAME>
  service: http://127.0.0.1:10080
```

Configure the DNS route and use `https://<YOUR_WEBDAV_HOSTNAME>/` in the plugin.
Pass through WebDAV methods and the `Authorization` header. Interactive browser
login pages in front of WebDAV require compatible client authentication.
The admin interface remains on loopback. Plain HTTP WebDAV sends credentials and
notes without transport encryption, so use HTTPS outside a trusted LAN.
SFTP is also available on port `2022` with the same file-user credentials.
SFTPGo host ports and bind addresses are hardcoded in `compose.yml`.

`backup.sh` briefly stops SFTPGo to archive both volumes consistently, then
restarts it (including on backup failure). Restore both archives together using
section 6 of `RESTORE.md`.

## Paperless-ngx setup

Paperless-ngx is an open-source document management system that transforms physical and digital documents into searchable, organized archives using OCR, tagging, and machine-learning classification.

### Components

The Paperless-ngx stack is configured with:
- **`paperless`**: Core application container running the web interface, workers, OCR engine (Tesseract), and document consumer (`ghcr.io/paperless-ngx/paperless-ngx:latest`).
- **`paperless-postgres`**: Dedicated PostgreSQL database (`postgres:17-alpine`).
- **`paperless-redis`**: Redis message broker (`redis:7-alpine`) for background task queues.

### Initial Setup & Creating Admin User

1. Start Paperless-ngx along with its dependencies:
   ```bash
   cd /opt/homelab
   docker compose pull paperless-postgres paperless-redis paperless
   docker compose up -d paperless-postgres paperless-redis paperless
   ```

2. Create your administrator account (superuser):
   ```bash
   docker compose exec -it paperless python3 manage.py createsuperuser
   ```
   Follow the prompts to specify a username, email, and password.

3. Access the Paperless-ngx web interface at `http://<SERVER_IP>:8010` (or `http://localhost:8010`) and log in.

### Remote Access via Reverse Proxy / Cloudflare Tunnel

To route remote access through Cloudflare Tunnel:
1. Route your hostname (e.g., `docs.example.com`) to `http://127.0.0.1:8010`.
2. Update `.env` to include your public URL for CSRF protection:
   ```bash
   PAPERLESS_URL=https://docs.example.com
   ```
3. Restart Paperless:
   ```bash
   docker compose up -d paperless
   ```

## Backup & Restoration

- **Nextcloud AIO (Built-in BorgBackup)**:
  - Managed via Nextcloud AIO Web Interface (`https://<YOUR_SERVER_IP>:8080`).
  - Safely stops child containers, performs an encrypted/deduplicated Borg snapshot of database & files, and restarts containers automatically.
- **Vikunja, Vaultwarden & Paperless-ngx (`backup.sh`)**:
  - Dumps PostgreSQL database (`paperless-postgres`) & MariaDB (`vikunja-mariadb`).
  - Archives persistent Docker named volumes (`vikunja_files`, `vikunja_db_data`, `nextcloud_aio_mastercontainer`, `vaultwarden_data`, `paperless_data`, `paperless_media`, `paperless_db_data`) into portable tarballs (`$BACKUP_ROOT/$DATE/volumes/*.tgz`).
  - Supports optional off-host sync using Restic (`RESTIC_REPOSITORY`).
- **SFTPGo (`backup.sh`)**: Archives `sftpgo_data` and `sftpgo_config` with the service stopped for a consistent snapshot.
- **Restoration**:
  - Deploy the stack on any host using `docker compose up -d`.
  - Extract volume archives or restore database dumps for Vikunja, Vaultwarden, and Paperless-ngx.
  - Nextcloud AIO is restored via the AIO Web Interface using your BorgBackup passphrase & archive path.
  - Follow `RESTORE.md` for step-by-step disaster recovery instructions.
