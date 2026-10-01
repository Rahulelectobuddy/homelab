#!/usr/bin/env bash
set -euo pipefail
cd /opt/homelab

echo "==> Validating compose"
docker compose config -q

echo "==> Pulling images"
docker compose pull

echo "==> Starting services"
docker compose up -d --remove-orphans

echo "==> Status"
docker compose ps
