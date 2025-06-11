#!/usr/bin/env bash

# Exit on errors
set -e
trap 'echo -e "\n\033[1;31m❌ Error on line $LINENO. Exiting!\033[0m"; exit 1' ERR

# Import community helper functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Use the exact variable names required by build.func
CTID="${1:-}"
HOSTNAME="${2:-}"
APP="Postiz"
DISK="12"
CPU="2"
RAM="4096"
OS="ubuntu"
VERSION="24.04"
UNPRIVILEGED="1"
NET="name=eth0,bridge=vmbr0,ip=dhcp"
TAGS="postiz;scheduler"

# Validate usage
if [[ -z "$CTID" || -z "$HOSTNAME" ]]; then
  echo -e "\033[1;31mUsage: $0 <CTID> <HOSTNAME>\033[0m"
  exit 1
fi

# Create the LXC container with community helpers
build_container

# Install Docker & Postiz stack
echo -e "\033[1;33m📦 Installing Docker & Docker Compose...\033[0m"
pct exec "$CTID" -- bash -lc "apt update && apt install -y ca-certificates curl gnupg lsb-release"
pct exec "$CTID" -- bash -lc "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
pct exec "$CTID" -- bash -lc "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$UBUNTU_CODENAME) stable\" | tee /etc/apt/sources.list.d/docker.list"
pct exec "$CTID" -- bash -lc "apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
pct exec "$CTID" -- bash -lc "systemctl enable docker --now"

echo -e "\033[1;33m🚀 Deploying Postiz stack via Docker Compose...\033[0m"
pct exec "$CTID" -- bash -lc "
cd /root && mkdir -p postiz && cd postiz
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  postiz:
    image: ghcr.io/gitroomhq/postiz-app:latest
    container_name: postiz
    restart: always
    environment:
      MAIN_URL: \"http://\$(hostname -I | awk '{print \$1}'):5000\"
      FRONTEND_URL: \"http://\$(hostname -I | awk '{print \$1}'):5000\"
      NEXT_PUBLIC_BACKEND_URL: \"http://\$(hostname -I | awk '{print \$1}'):5000/api\"
      JWT_SECRET: \"$(head -c 32 /dev/urandom | base64)\"
      DATABASE_URL: \"postgresql://postiz-user:postiz-password@postiz-postgres:5432/postiz-db-local\"
      REDIS_URL: \"redis://postiz-redis:6379\"
      BACKEND_INTERNAL_URL: \"http://localhost:3000\"
      IS_GENERAL: \"true\"
      DISABLE_REGISTRATION: \"false\"
      STORAGE_PROVIDER: \"local\"
      UPLOAD_DIRECTORY: \"/uploads\"
      NEXT_PUBLIC_UPLOAD_DIRECTORY: \"/uploads\"
      NOT_SECURED: \"true\"
    volumes:
      - postiz-config:/config
      - postiz-uploads:/uploads
    ports:
      - 5000:5000
    networks:
      - postiz-network
    depends_on:
      postiz-postgres:
        condition: service_healthy
      postiz-redis:
        condition: service_healthy

  postiz-postgres:
    image: postgres:17-alpine
    container_name: postiz-postgres
    restart: always
    environment:
      POSTGRES_PASSWORD: postiz-password
      POSTGRES_USER: postiz-user
      POSTGRES_DB: postiz-db-local
    volumes:
      - postgres-volume:/var/lib/postgresql/data
    healthcheck:
      test: pg_isready -U postiz-user -d postiz-db-local
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - postiz-network

  postiz-redis:
    image: redis:7.2
    container_name: postiz-redis
    restart: always
    healthcheck:
      test: redis-cli ping
      interval: 10s
      timeout: 3s
      retries: 3
    volumes:
      - postiz-redis-data:/data
    networks:
      - postiz-network

volumes:
  postgres-volume:
  postiz-redis-data:
  postiz-config:
  postiz-uploads:

networks:
  postiz-network:
EOF
docker compose up -d
"

# Final Message
LXC_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo -e "\n\033[1;32m🎉✅ Postiz is deployed in LXC $CTID ($HOSTNAME).\033[0m"
echo -e "\033[1;32m🔗 Access it at: http://$LXC_IP:5000\033[0m"
echo -e "\033[1;32m🙏 Thanks for using Peterxmadeit's repo!\033[0m"
