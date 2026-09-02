#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
TEMPLATE_ID=8000

# Target Gitea LXC Details
GITEA_CT_ID=402
GITEA_CT_NAME="dev-gitea"
STORAGE_POOL="local-lvm"
DISK_SIZE="25G"
CORES=2
MEMORY=1024                       # in MB
BRIDGE="vmbr0"
IP_ADDR="192.168.1.102/24"
GATEWAY="192.168.1.1"

CLEAN_IP="${IP_ADDR%/*}"
GITEA_URL="http://${CLEAN_IP}:3000/"

# Target PostgreSQL LXC Details (CT 401)
DB_CT_ID=401
DB_HOST="192.168.1.101"
DB_PORT="5432"
GITEA_DB_NAME="gitea"
GITEA_DB_USER="gitea"
GITEA_DB_PASS="SecureGiteaPass123!"

# Gitea Web Admin Account Details
ADMIN_USER="admin-sri"
ADMIN_PASSWORD="SecureGiteaPass123"
ADMIN_EMAIL="admin@sriitservicesllc.com"

# ==============================================================================
# Pre-flight Checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must run as root on the Proxmox host." >&2
   exit 1
fi

if ! pct status "$TEMPLATE_ID" &>/dev/null; then
    echo "[ERROR] Base template CT $TEMPLATE_ID does not exist." >&2
    exit 1
fi

if ! pct status "$DB_CT_ID" &>/dev/null; then
    echo "[ERROR] PostgreSQL container CT $DB_CT_ID does not exist." >&2
    exit 1
fi

if [[ "$(pct status "$DB_CT_ID")" != *"status: running"* ]]; then
    echo "[ERROR] PostgreSQL container CT $DB_CT_ID must be running. Start it first: pct start $DB_CT_ID" >&2
    exit 1
fi

if pct status "$GITEA_CT_ID" &>/dev/null; then
    echo "[ERROR] Container $GITEA_CT_ID already exists. Destroy it first with: pct destroy $GITEA_CT_ID" >&2
    exit 1
fi

# ==============================================================================
# Step 1: Provision Database & User in PostgreSQL Container (401)
# ==============================================================================
echo "[1/6] Provisioning database '$GITEA_DB_NAME' and user on CT $DB_CT_ID..."

pct exec "$DB_CT_ID" -- su - postgres -c \
    "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='$GITEA_DB_USER'\" | grep -q 1 || \
     psql -c \"CREATE USER $GITEA_DB_USER WITH ENCRYPTED PASSWORD '$GITEA_DB_PASS';\""

pct exec "$DB_CT_ID" -- su - postgres -c \
    "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$GITEA_DB_NAME'\" | grep -q 1 || \
     psql -c \"CREATE DATABASE $GITEA_DB_NAME WITH OWNER $GITEA_DB_USER;\""

pct exec "$DB_CT_ID" -- su - postgres -c \
    "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $GITEA_DB_NAME TO $GITEA_DB_USER;\""

# ==============================================================================
# Step 2: Clone from Base Template
# ==============================================================================
echo "[2/6] Cloning Gitea CT $GITEA_CT_ID from Template $TEMPLATE_ID..."
pct clone "$TEMPLATE_ID" "$GITEA_CT_ID" --hostname "$GITEA_CT_NAME" --full 1

pct set "$GITEA_CT_ID" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap 512 \
    --net0 name=eth0,bridge="$BRIDGE",ip="$IP_ADDR",gw="$GATEWAY" \
    --onboot 1

pct resize "$GITEA_CT_ID" rootfs "$DISK_SIZE"

echo "Starting container $GITEA_CT_ID..."
pct start "$GITEA_CT_ID"
sleep 4

# ==============================================================================
# Step 3: Install Dependencies & Download Gitea Binary
# ==============================================================================
echo "[3/6] Installing dependencies and downloading Gitea..."
pct exec "$GITEA_CT_ID" -- apt update
pct exec "$GITEA_CT_ID" -- apt install -y git postgresql-client curl openssl

# Create git service user
pct exec "$GITEA_CT_ID" -- id -u git &>/dev/null || \
pct exec "$GITEA_CT_ID" -- adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git

# Download binary
pct exec "$GITEA_CT_ID" -- curl -Lo /usr/local/bin/gitea https://dl.gitea.com/gitea/1.27.3/gitea-1.27.3-linux-amd64
pct exec "$GITEA_CT_ID" -- chmod +x /usr/local/bin/gitea

# Create directory structure
pct exec "$GITEA_CT_ID" -- mkdir -p /var/lib/gitea/{custom,data,log} /etc/gitea /home/git/gitea-repositories
pct exec "$GITEA_CT_ID" -- chown -R git:git /var/lib/gitea /etc/gitea /home/git/gitea-repositories
pct exec "$GITEA_CT_ID" -- chmod 750 /etc/gitea

# ==============================================================================
# Step 4: Configure app.ini (Postgres Backend) & Systemd
# ==============================================================================
echo "[4/6] Generating app.ini and configuring systemd service..."

SECRET_KEY=$(openssl rand -hex 16)
INTERNAL_TOKEN=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -base64 32)

pct exec "$GITEA_CT_ID" -- bash -c "cat << EOF > /etc/gitea/app.ini
APP_NAME = Gitea: Git with a cup of tea
RUN_USER = git
WORK_PATH = /var/lib/gitea
RUN_MODE = prod

[database]
DB_TYPE  = postgres
HOST     = ${DB_HOST}:${DB_PORT}
NAME     = ${GITEA_DB_NAME}
USER     = ${GITEA_DB_USER}
PASSWD   = ${GITEA_DB_PASS}
SCHEMA   = public
SSL_MODE = disable

[repository]
ROOT = /home/git/gitea-repositories

[server]
SSH_DOMAIN       = ${CLEAN_IP}
HTTP_PORT        = 3000
ROOT_URL         = ${GITEA_URL}
DISABLE_SSH      = false
SSH_PORT         = 22
START_SSH_SERVER = false

[security]
INSTALL_LOCK   = true
SECRET_KEY     = ${SECRET_KEY}
INTERNAL_TOKEN = ${INTERNAL_TOKEN}

[oauth2]
JWT_SECRET     = ${JWT_SECRET}

[service]
DISABLE_REGISTRATION = false
ENABLE_CAPTCHA       = false

[actions]
ENABLED = true
EOF"

# Ensure git user has write permission on app.ini to prevent permission errors
pct exec "$GITEA_CT_ID" -- chown -R git:git /etc/gitea
pct exec "$GITEA_CT_ID" -- chmod 660 /etc/gitea/app.ini

# Register Systemd Unit
pct exec "$GITEA_CT_ID" -- bash -c "cat << 'EOF' > /etc/systemd/system/gitea.service
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF"

pct exec "$GITEA_CT_ID" -- systemctl daemon-reload
pct exec "$GITEA_CT_ID" -- systemctl enable --now gitea

# ==============================================================================
# Step 5: Provision Gitea Admin User
# ==============================================================================
echo "[5/6] Waiting for Gitea to finish database migrations..."
sleep 6

echo "[6/6] Creating initial admin user '$ADMIN_USER'..."
pct exec "$GITEA_CT_ID" -- su - git -c \
    "/usr/local/bin/gitea admin user create \
        --config /etc/gitea/app.ini \
        --username '$ADMIN_USER' \
        --password '$ADMIN_PASSWORD' \
        --email '$ADMIN_EMAIL' \
        --admin"

echo "------------------------------------------------------------------------"
echo "=== Gitea Successfully Deployed! ==="
echo "Container ID   : $GITEA_CT_ID"
echo "Access URL     : $GITEA_URL"
echo "Database       : PostgreSQL at $DB_HOST:$DB_PORT/$GITEA_DB_NAME"
echo "Admin Username : $ADMIN_USER"
echo "Admin Password : $ADMIN_PASSWORD"
echo "Admin Email    : $ADMIN_EMAIL"
echo "------------------------------------------------------------------------"