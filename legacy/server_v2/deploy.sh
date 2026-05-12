#!/usr/bin/env bash
# deploy.sh — build and restart the server on the VM
# Run from /opt/bubbles/repo/server_v2/
# Usage: ./deploy.sh [optional-git-branch]
set -euo pipefail

BRANCH="${1:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Pulling latest code (branch: $BRANCH)..."
cd "$SCRIPT_DIR/.."
git fetch --all
git checkout "$BRANCH"
git pull origin "$BRANCH"

echo "==> Building Docker image..."
cd "$SCRIPT_DIR"
docker build -t bubbles-server:latest .

echo "==> Restarting containers..."
docker compose -f docker-compose.prod.yml down --remove-orphans
docker compose -f docker-compose.prod.yml up -d

echo "==> Waiting for health check (up to 120 s)..."
for i in $(seq 1 24); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "✅  Server healthy (${STATUS}) after ~$((i*5)) seconds."
    exit 0
  fi
  echo "   waiting... ($((i*5))s, last status: $STATUS)"
  sleep 5
done

echo "❌  Server did not become healthy within 120 s. Check logs:"
echo "    docker compose -f docker-compose.prod.yml logs --tail=50 server"
exit 1
