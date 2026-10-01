#!/usr/bin/env bash
set -euo pipefail

echo "========================================================="
echo " WARNING: This script will perform a full Docker cleanup!"
echo " It will:"
echo "   1. Stop and remove all Docker containers"
echo "   2. Remove unused Docker images, networks, and volumes"
echo "   3. (Optional) Clean up legacy persistent host data directories"
echo "========================================================="

read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo "==> Stopping Docker Compose services in current directory..."
if [ -f "compose.yml" ] || [ -f "docker-compose.yml" ]; then
  docker compose down --volumes --remove-orphans || true
fi

echo "==> Stopping all running containers..."
CONTAINERS=$(docker ps -aq)
if [ -n "$CONTAINERS" ]; then
  docker stop $CONTAINERS || true
  docker rm -f $CONTAINERS || true
fi

echo "==> Pruning Docker system (containers, images, volumes, networks)..."
docker system prune -af --volumes

echo "==> Docker cleanup complete!"

echo ""
read -p "Do you also want to remove legacy /home/rahul/ app data directories? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "==> Removing legacy app directories..."
  DIRS=(
    "/home/rahul/immich"
    "/home/rahul/jellyfin"
    "/home/rahul/paperless"
    "/home/rahul/homepage"
    "/home/rahul/docmost"
    "/home/rahul/metube"
    "/home/rahul/mealie"
    "/home/rahul/qbittorrent"
    "/home/rahul/zulip"
  )
  for d in "${DIRS[@]}"; do
    if [ -d "$d" ]; then
      echo "  Removing $d..."
      sudo rm -rf "$d"
    fi
  done
  echo "==> Legacy data directories removed!"
fi

echo "==> System clean and ready for fresh deployment."
