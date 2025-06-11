#!/usr/bin/env bash
# Postiz LXC Installer using community-scripts' build.func for reliable LXC setup

set -e
trap 'echo -e "\n\033[1;31m❌ Error on line $LINENO. Exiting!\033[0m"; exit 1' ERR

# Import the community functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# LXC container settings
var_ctid="${1:-}"
var_hostname="${2:-}"
var_os="ubuntu"
var_os_version="24.04"
var_disk="12"
var_cpu="2"
var_ram="4096"
var_unprivileged="1"
var_net="name=eth0,bridge=vmbr0,ip=dhcp"

# Basic usage check
if [[ -z "$var_ctid" || -z "$var_hostname" ]]; then
  echo -e "\033[1;31mUsage: $0 <CTID> <HOSTNAME>\033[0m"
  exit 1
fi

# Build LXC container using community helper
build_container

# Post-deployment: install Docker & Postiz stack
echo -e "\033[1;33m📦 Installing Docker & Docker Compose inside LXC...\033[0m"
pct exec "$var_ctid" -- bash -c "apt update && apt install -y ca-certificates curl gnupg lsb-release"
pct exec "$var_ctid" -- bash -c "mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
pct exec "$var_ctid" -- bash -c "echo \
  \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$UBUNTU_CODENAME) stable\" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null"
pct exec "$var_ctid" -- bash -c "apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
pct exec "$var_ctid" -- bash -c "systemctl enable docker --now"

echo -e "\033[1;33m🚀 Deploying Postiz stack via Docker Compose...\033[0m"
pct exec "$var_ctid" -- bash -c "
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

# Final message
LXC_IP=$(pct exec "$var_ctid" -- hostname -I | awk '{print $1}')
echo -e "\n\033[1;32m🎉✅ Postiz has been deployed in LXC container $var_ctid ($var_hostname).\033[0m"
echo -e "\033[1;32m🔗 Access it at: http://$LXC_IP:5000\033[0m"
echo -e "\033[1;32m🙏 Thank you for using Peterxmadeit's repo!\033[0m"
