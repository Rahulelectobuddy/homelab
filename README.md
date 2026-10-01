# Homelab Infrastructure

Single Docker Compose deployment for the current homelab services.

## Design

- Git repository = desired state: Compose, scripts, documentation, workflow.
- `/opt/homelab/.env` = server-only secrets; never committed.
- `/home/rahul/...` = persistent application data.
- `/opt/backups/homelab` = temporary/local backup staging.
- Restic = encrypted off-host backup target.
- Nextcloud AIO = backed up using its own AIO backup mechanism; its child containers are intentionally not manually merged into this Compose file.
- GitHub Actions self-hosted runner = deployment mechanism.

## First deployment

```bash
sudo mkdir -p /opt/homelab
sudo chown "$USER":"$USER" /opt/homelab
git clone <YOUR_REPO> /opt/homelab
cp .env.example .env
chmod 600 .env
nano .env

docker compose config
docker compose pull
docker compose up -d
docker compose ps
```

## CI/CD

The GitHub Actions runner should run on the same server. The workflow:

1. checks out the repository
2. validates Compose
3. syncs the repository into `/opt/homelab`
4. deliberately preserves `/opt/homelab/.env`
5. runs `deploy.sh`

The runner account therefore needs write access to `/opt/homelab` and Docker access. Treat this runner as a privileged production component.

For a safer setup, keep the runner dedicated to this homelab repository and do not let arbitrary repositories use the same runner.

## Recovery principle

A new server should be recoverable from:

1. Git repository
2. `.env` / secret recovery source
3. Backup repository
4. AIO backup for Nextcloud
5. Docker installation

Do not depend on the old server's Docker state, manually created containers, or Portainer UI configuration.

## Important

The original configuration contained plaintext secrets. Rotate all passwords/keys that were exposed before treating this repository as secure.


## Backup architecture

Think of the system as four layers:

```text
GitHub
  └── Compose + scripts + workflows + documentation

Secret store
  └── .env / encryption keys / passwords

Restic repository (off-host)
  ├── application files
  ├── media
  ├── Compose repository
  ├── database logical dumps
  └── Zulip named-volume archives

Nextcloud AIO backup
  └── AIO-managed Nextcloud backup
```

The important distinction is:

- **Git is not a backup of application data.**
- **A Docker image is not a backup of application state.**
- **A database directory is not a substitute for a logical database dump.**
- **A backup that has never been restored is only a hypothesis.**

Use at least one backup destination that is physically or logically separate from the server.

## Before first restart

1. Rotate every credential that was present in the old Compose files.
2. Confirm `/home/rahul/immich/library` is where Immich's actual library should live.
3. Confirm existing application data directories still exist.
4. Create `.env` from `.env.example`.
5. Run `docker compose config -q`.
6. Take a backup/snapshot of the current host before destructive cleanup.
