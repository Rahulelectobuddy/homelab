# Homelab Infrastructure

Single Docker Compose deployment for **Nextcloud AIO**, **Vikunja**, **n8n**, **Vaultwarden** (Bitwarden-compatible Password Manager), **Zulip**, and **SFTPGo** for Obsidian WebDAV sync.

## Design

- **Git repository = desired state**: Docker Compose file, backup/deploy scripts, and documentation.
- **`/opt/homelab/.env`**: Secret configuration for existing services (never committed). Zulip settings and generated credentials are inline in `compose.yml`, which must be kept private.
- **Docker Named Volumes**: All persistent data is stored in isolated Docker named volumes (`n8n_data`, `n8n_db_data`, `vikunja_files`, `vikunja_db_data`, `nextcloud_aio_mastercontainer`, `vaultwarden_data`, `sftpgo_data`, `sftpgo_config`) without host-path dependencies.
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
- **SFTPGo**: Admin `127.0.0.1:8089`, WebDAV `10080`, SFTP `2022`
- **Zulip**: HTTP origin `127.0.0.1:8090`, public HTTPS via Cloudflare Tunnel

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

## Zulip setup

Zulip uses the official `ghcr.io/zulip/zulip-server:12.3-0` image with dedicated
PostgreSQL, RabbitMQ, Redis, and authenticated Memcached services. All five
start with the stack, without profiles or Zulip `.env` entries. Five independent
random credentials are defined in `x-zulip-credentials` and shared using YAML
anchors. Preserve these values on redeployment and recovery; changing the
PostgreSQL password requires also updating the initialized database role.
Allow at least 2 GB of available RAM for Zulip and its dependencies.

1. Zulip is configured for `talk.cypherlifeos.space`, administrator
   `rahulyugalgarg@gmail.com`, and local email files instead of SMTP.
   Keep `compose.yml` private because it contains the generated passwords.
2. In the host's Cloudflare Tunnel configuration, route
   `talk.cypherlifeos.space` to **`http://127.0.0.1:8090`**. A local ingress rule
   looks like this (place before the existing catch-all rule):

   ```yaml
   - hostname: talk.cypherlifeos.space
     service: http://127.0.0.1:8090
   ```

   Configure the public DNS route and keep public requests on HTTPS. Zulip's
   origin is bound to host loopback. `TRUST_GATEWAY_IP: "true"` trusts the
   Docker gateway used by host-based cloudflared, allowing its forwarded HTTPS
   and client IP headers. See the official
   [reverse proxy configuration](https://zulip.readthedocs.io/projects/docker/en/latest/how-to/compose-ssl.html#deploying-behind-a-reverse-proxy).
3. Initialize and start Zulip on the homelab host:

   ```bash
   cd /opt/homelab
   docker compose config --quiet
   docker compose pull zulip zulip-postgres zulip-memcached zulip-rabbitmq zulip-redis
   docker compose run --rm zulip app:init
   docker compose up -d --wait zulip
   docker compose exec -T -u zulip zulip \
     /home/zulip/deployments/current/manage.py generate_realm_creation_link
   ```

   Open the generated link to create your organization and first administrator.
   Normal updates continue through `deploy.sh` and the existing deployment workflow.
   See the official [first-run instructions](https://zulip.readthedocs.io/projects/docker/en/latest/how-to/compose-getting-started.html).

Zulip persists uploads, configuration, and secrets in `zulip_data`; its database,
queue, and Redis use `zulip_db_data`, `zulip_rabbitmq_data`, and `zulip_redis_data`.
`backup.sh` refreshes Zulip's logical database dump inside `zulip_data/backups`
when Zulip is running, then archives `zulip_data.tgz`. Backups contain secrets;
store them securely. Zulip also creates daily database dumps in this volume;
monitor their storage usage. Use the Zulip recovery section in `RESTORE.md`
instead of copying a running database volume.

### Running without SMTP

The file email backend is already configured directly in `compose.yml`.
No SMTP credentials are required.
The file backend writes outgoing emails to `/var/log/zulip/emails` inside the
container. Chat works, but invitations, verification links, and password resets
must be retrieved manually; email notifications are not delivered to inboxes.
Retrieve email files with:

```bash
docker compose exec -u zulip zulip ls -lt /var/log/zulip/emails
docker compose exec -u zulip zulip cat /var/log/zulip/emails/<FILENAME>
```

These files contain private account links and are temporary container data.
To enable SMTP later, change `SETTING_EMAIL_BACKEND` to
`django.core.mail.backends.smtp.EmailBackend`, add the SMTP `SETTING_EMAIL_*`
values and `SECRETS_email_password` to the Zulip environment, then recreate Zulip. See [Zulip's documented file backend](https://zulip.readthedocs.io/en/stable/production/email.html#logging-outgoing-email-to-a-file-for-prototyping).

## Backup & Restoration

- **Nextcloud AIO (Built-in BorgBackup)**:
  - Managed via Nextcloud AIO Web Interface (`https://<YOUR_SERVER_IP>:8080`).
  - Safely stops child containers, performs an encrypted/deduplicated Borg snapshot of database & files, and restarts containers automatically.
- **n8n, Vikunja & Vaultwarden (`backup.sh`)**:
  - Dumps PostgreSQL (`n8n-postgres`) & MariaDB (`vikunja-mariadb`).
  - Archives persistent Docker named volumes (`n8n_data`, `n8n_db_data`, `vikunja_files`, `vikunja_db_data`, `vaultwarden_data`, `nextcloud_aio_mastercontainer`) into portable tarballs (`$BACKUP_ROOT/$DATE/volumes/*.tgz`).
  - Supports optional off-host sync using Restic (`RESTIC_REPOSITORY`).
- **SFTPGo (`backup.sh`)**: Archives `sftpgo_data` and `sftpgo_config` with the service stopped for a consistent snapshot.
- **Restoration**:
  - Deploy the stack on any host using `docker-compose up -d`.
  - Extract volume archives or restore database dumps for n8n, Vikunja, and Vaultwarden.
  - Nextcloud AIO is restored via the AIO Web Interface using your BorgBackup passphrase & archive path.




