# GitHub Webhook Deployer

Automated deployment system that listens for GitHub webhook events and deploys applications using Docker Compose.

## Features

- 🔄 Auto-deploy on push to master branch
- 🐳 Docker Compose integration
- 📝 Auto-rotating logs (2-day retention)
- ⚙️ Centralized configuration
- 🚀 Force recreation of containers on each deploy

## Directory Structure

```
/data/apps/
├── github-webhook-deployer/     # This repository
│   ├── listener.sh              # Webhook listener
│   ├── deploy.sh                # Deployment script
│   ├── config.env               # Configuration
│   ├── setup.sh                 # Installation script
│   └── logs/                    # Auto-created log directory
└── your-project-name/           # Your deployed projects
```

## Prerequisites

- Docker and Docker Compose
- `jq` and `netcat`: `sudo apt-get install jq netcat`
- Git with SSH access to GitHub
- Sudo privileges

## Quick Start

After cloning this repo to `/data/apps/github-webhook-deployer/`:

```bash
cd /data/apps/github-webhook-deployer

# 1. Make setup script executable
chmod +x setup.sh

# 2. Run setup script
sudo ./setup.sh

# 3. Verify SSH access to GitHub (important!)
ssh -T git@github.com
# Should say: "Hi <username>! You've successfully authenticated"

# 4. Start the service
sudo systemctl start github-webhook-deployer.service

# 5. Check it's running
sudo systemctl status github-webhook-deployer.service
```

That's it! The webhook listener is now running on port 9021.

**Note**: If you don't have an SSH key, generate one first:

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
cat ~/.ssh/id_ed25519.pub  # Copy this to GitHub → Settings → SSH Keys
```

## Configuration

Edit `config.env` to customize settings:

```bash
nano /data/apps/github-webhook-deployer/config.env
```

Key settings:

- `WEBHOOK_PORT=9021` - Webhook listener port
- `PROJECTS_BASE_DIR="/data/apps"` - Where projects are deployed
- `DEFAULT_BRANCH="master"` - Branch to auto-deploy
- `LOG_RETENTION_DAYS=2` - Days to keep logs

After changing config, restart the service:

```bash
sudo systemctl restart github-webhook-deployer.service
```

## GitHub Webhook Setup

1. Go to your GitHub repo → **Settings** → **Webhooks** → **Add webhook**
2. Configure:
    - **Payload URL**: `http://webhook.hashcode.md:9021`
    - **Content type**: `application/json`
    - **Events**: Just the push event
    - **Active**: ✓

3. Open firewall port:

```bash
sudo ufw allow 9021/tcp
```

## How It Works

1. GitHub sends webhook on push
2. Listener validates payload and extracts project/branch info
3. If branch is `master`, triggers deployment:
    - Clones repo (if first time) or fetches latest changes
    - Resets to `origin/master` (discards local changes)
    - Runs `docker compose down && docker compose up -d --build --force-recreate`
4. Logs everything with timestamps

## Common Commands

**View logs:**

```bash
# Listener logs (webhook events)
tail -f /data/apps/github-webhook-deployer/logs/listener.log

# Deployment logs (git & docker operations)
tail -f /data/apps/github-webhook-deployer/logs/deploy.log

# Service logs
sudo journalctl -u github-webhook-deployer.service -f
```

**Service management:**

```bash
# Status
sudo systemctl status github-webhook-deployer.service

# Restart
sudo systemctl restart github-webhook-deployer.service

# Stop
sudo systemctl stop github-webhook-deployer.service

# Disable auto-start
sudo systemctl disable github-webhook-deployer.service
```

**Manual deployment:**

```bash
cd /data/apps/github-webhook-deployer
./deploy.sh <project-name> [branch]
```

## Troubleshooting

**Service won't start:**

```bash
# Check status and errors
sudo systemctl status github-webhook-deployer.service
sudo journalctl -u github-webhook-deployer.service -n 50

# Verify permissions
ls -l /data/apps/github-webhook-deployer/*.sh
# Should show: -rwxr-xr-x
```

**Port in use:**

```bash
sudo lsof -i :9021
# Change port in config.env if needed
```

**Webhook not triggering:**

```bash
# Check listener logs
tail -f /data/apps/github-webhook-deployer/logs/listener.log

# Test manually
curl -X POST http://localhost:9021 \
  -H "Content-Type: application/json" \
  -d '{"ref":"refs/heads/master","repository":{"full_name":"YourUser/your-repo"}}'
```

**Deployment fails:**

```bash
# Check deployment logs
tail -f /data/apps/github-webhook-deployer/logs/deploy.log

# Common issues:
# - SSH key not configured for GitHub
# - Docker not running: sudo systemctl status docker
# - Missing docker-compose.yml in project
```

**GitHub SSH issues:**

```bash
# Test connection
ssh -T git@github.com

# Add SSH key if needed
cat ~/.ssh/id_ed25519.pub
# Copy to GitHub → Settings → SSH Keys
```

## Uninstall

```bash
sudo systemctl stop github-webhook-deployer.service
sudo systemctl disable github-webhook-deployer.service
sudo rm /etc/systemd/system/github-webhook-deployer.service
sudo systemctl daemon-reload
```

## Security Notes

- Service runs as root (required for Docker)
- Restrict webhook port to GitHub IPs in production
- Keep SSH keys secure
- Review logs regularly

---

**Port**: 9021 | **Logs**: Auto-delete after 2 days | **Branch**: master only