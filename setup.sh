#!/bin/bash
set -euo pipefail

# Setup script for GitHub Webhook Deployer
# Run this after cloning the repo to /data/apps/github-webhook-deployer

echo "=========================================="
echo "GitHub Webhook Deployer - Setup"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Get the directory where this script is located
WEBHOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="/etc/systemd/system/github-webhook-deployer.service"

echo "Installation directory: $WEBHOOK_DIR"
echo ""

echo "Step 1: Checking prerequisites..."

# Check for required commands
MISSING_DEPS=()

if ! command -v docker &> /dev/null; then
    MISSING_DEPS+=("docker")
fi

if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
fi

if ! command -v nc &> /dev/null; then
    MISSING_DEPS+=("netcat")
fi

if ! command -v git &> /dev/null; then
    MISSING_DEPS+=("git")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "ERROR: Missing required dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "Install them with:"
    echo "  sudo apt-get install -y ${MISSING_DEPS[*]}"
    exit 1
fi

echo "✓ All prerequisites installed"
echo ""

echo "Step 2: Creating log directory..."
mkdir -p "$WEBHOOK_DIR/logs"
echo "✓ Created $WEBHOOK_DIR/logs"
echo ""

echo "Step 3: Setting permissions..."
chmod +x "$WEBHOOK_DIR/listener.sh"
chmod +x "$WEBHOOK_DIR/deploy.sh"
chmod 644 "$WEBHOOK_DIR/config.env"

# Get the actual owner of the webhook directory
OWNER=$(stat -c '%U' "$WEBHOOK_DIR")
GROUP=$(stat -c '%G' "$WEBHOOK_DIR")

# Set ownership for logs directory to match the directory owner
chown -R "$OWNER:$GROUP" "$WEBHOOK_DIR/logs"
echo "✓ Permissions set (logs owned by $OWNER:$GROUP)"
echo ""

echo "Step 4: Installing systemd service..."
if [ -f "$WEBHOOK_DIR/github-webhook-deployer.service" ]; then
    # Update the service file with the actual user/group
    sed "s/User=saniok1122/User=$OWNER/" "$WEBHOOK_DIR/github-webhook-deployer.service" | \
    sed "s/Group=saniok1122/Group=$GROUP/" > "$SERVICE_FILE"

    systemctl daemon-reload
    systemctl enable github-webhook-deployer.service
    echo "✓ Service installed and enabled (running as $OWNER:$GROUP)"
else
    echo "ERROR: github-webhook-deployer.service not found in $WEBHOOK_DIR"
    exit 1
fi
echo ""

echo "Step 5: Verifying configuration..."
source "$WEBHOOK_DIR/config.env"
echo "  - Webhook Port: $WEBHOOK_PORT"
echo "  - Projects Directory: $PROJECTS_BASE_DIR"
echo "  - Default Branch: $DEFAULT_BRANCH"
echo "  - Log Retention: $LOG_RETENTION_DAYS days"
echo ""

echo "Step 6: Configuring Git and SSH..."
# Configure git safe directory for the owner user
sudo -u "$OWNER" git config --global --add safe.directory '/data/apps/*'
echo "✓ Git safe directory configured"

# Check if SSH key exists for the owner
SSH_KEY_EXISTS=false
if sudo -u "$OWNER" test -f "/home/$OWNER/.ssh/id_rsa" || \
   sudo -u "$OWNER" test -f "/home/$OWNER/.ssh/id_ed25519"; then
    SSH_KEY_EXISTS=true
fi

# Add GitHub to known hosts for the owner
sudo -u "$OWNER" mkdir -p "/home/$OWNER/.ssh"
sudo -u "$OWNER" ssh-keyscan github.com >> "/home/$OWNER/.ssh/known_hosts" 2>/dev/null
echo "✓ GitHub added to known hosts"
echo ""

echo "=========================================="
echo "✓ Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Verify SSH access to GitHub (as $OWNER):"
if [ "$SSH_KEY_EXISTS" = true ]; then
    echo "   sudo -u $OWNER ssh -T git@github.com"
    echo "   (Should say: 'Hi <username>! You've successfully authenticated')"
else
    echo "   ⚠ WARNING: No SSH key found for $OWNER"
    echo "   Generate one with: ssh-keygen -t ed25519 -C 'your_email@example.com'"
    echo "   Then add it to GitHub: Settings → SSH Keys"
fi
echo ""
echo "2. Start the service:"
echo "   sudo systemctl start github-webhook-deployer.service"
echo ""
echo "3. Check status:"
echo "   sudo systemctl status github-webhook-deployer.service"
echo ""
echo "4. View logs:"
echo "   tail -f $WEBHOOK_DIR/logs/listener.log"
echo ""
echo "5. Configure GitHub webhook to:"
echo "   http://YOUR_SERVER_IP:$WEBHOOK_PORT"
echo ""
echo "6. Open firewall port:"
echo "   sudo ufw allow $WEBHOOK_PORT/tcp"
echo ""