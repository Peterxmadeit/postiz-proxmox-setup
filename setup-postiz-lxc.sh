#!/bin/bash
# Usage: ./setup-postiz-lxc.sh <CTID> <HOSTNAME>
# Example: ./setup-postiz-lxc.sh 105 postiz

CTID="$1"
HOSTNAME="$2"
TEMPLATE="local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst"

if [ -z "$CTID" ] || [ -z "$HOSTNAME" ]; then
  echo "Usage: $0 <CTID> <HOSTNAME>"
  exit 1
fi

# 1. Create LXC container
pct create $CTID $TEMPLATE \
  --hostname $HOSTNAME \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 2 --memory 4096 --disk 12 \
  --unprivileged 1

pct start $CTID

# 2. Install Docker & Docker Compose
pct exec $CTID -- bash -lc "apt update && apt install -y ca-certificates curl gnupg lsb-release"
pct exec $CTID -- bash -lc "mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
pct exec $CTID -- bash -lc "echo \
  \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$UBUNTU_CODENAME) stable\" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null"
pct exec $CTID -- bash -lc "apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
pct exec $CTID -- bash -lc "systemctl enable docker --now"

# 3. Setup Postiz stack
pct exec $CTID -- bash -lc "mkdir -p /root/postiz && cd /root/postiz && \
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
cd /root/postiz && docker compose up -d"

echo "✅ LXC container $CTID ($HOSTNAME) with Postiz is deploying. Visit: http://<LXC_IP>:5000 once setup completes."
# Display final message with LXC IP and port
LXC_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo -e "\n🎉✅ Postiz has been deployed in LXC container $CTID ($HOSTNAME)."
echo -e "🔗 Access it at: http://$LXC_IP:5000"
echo -e "🙏 Thank you for using peterxmadeits repo!"
