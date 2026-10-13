# Homelab Infrastructure

Single Docker Compose deployment for **Nextcloud AIO**, **Vikunja**, **n8n**, **Vaultwarden** (Bitwarden-compatible Password Manager), and **Zulip**.

## Design

- **Git repository = desired state**: Docker Compose file, backup/deploy scripts, and documentation.
- **`/opt/homelab/.env`**: Secret configuration for existing services (never committed). Zulip settings and generated credentials are inline in `compose.yml`, which must be kept private.
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
- **Zulip**: HTTP origin `127.0.0.1:8090`, public HTTPS via Cloudflare Tunnel

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
- **Restoration**:
  - Deploy the stack on any host using `docker-compose up -d`.
  - Extract volume archives or restore database dumps for n8n, Vikunja, and Vaultwarden.
  - Nextcloud AIO is restored via the AIO Web Interface using your BorgBackup passphrase & archive path.




