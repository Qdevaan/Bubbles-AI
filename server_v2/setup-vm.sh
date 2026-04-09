#!/usr/bin/env bash
# setup-vm.sh — run ONCE on a fresh Ubuntu 22.04 VM as root
# Oracle Cloud: sudo ./setup-vm.sh   |   AWS: sudo ./setup-vm.sh
set -euo pipefail

echo "==> Installing Docker + Docker Compose..."
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Allow the non-root ubuntu user to run Docker
usermod -aG docker ubuntu

echo "==> Creating /opt/bubbles directory structure..."
mkdir -p /opt/bubbles/env
chown -R ubuntu:ubuntu /opt/bubbles

echo ""
echo "✅  Setup complete. Now:"
echo "    1. Log out and back in so the docker group takes effect."
echo "    2. Copy your .env file:  scp env/.env ubuntu@<IP>:/opt/bubbles/env/.env"
echo "    3. Clone the repo:       cd /opt/bubbles && git clone <YOUR_REPO_URL> repo"
echo "    4. Run deploy script:    cd /opt/bubbles/repo/server_v2 && ./deploy.sh"
