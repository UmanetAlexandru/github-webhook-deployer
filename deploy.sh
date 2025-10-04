#!/bin/bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# -----------------------------------------------------------------------------
# Deployment Script
# -----------------------------------------------------------------------------
# Usage: ./deploy.sh <project_name> [branch]
#   <project_name>: Required. Name of the project (folder under PROJECTS_BASE_DIR).
#   [branch]: Optional. Git branch to reset to (default: from config).
# -----------------------------------------------------------------------------

PROJECT_NAME=${1:-}
BRANCH=${2:-$DEFAULT_BRANCH}

# Function to log messages
log_message() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ${level} - $*" | tee -a "$DEPLOY_LOG"
}

# Function to clean old logs
cleanup_old_logs() {
    find "$LOG_DIR" -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
}

# Validate input
if [ -z "$PROJECT_NAME" ]; then
    log_message "ERROR" "Usage: $0 <project_name> [branch]"
    exit 1
fi

PROJECT_PATH="${PROJECTS_BASE_DIR}/${PROJECT_NAME}"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Cleanup old logs
cleanup_old_logs

log_message "INFO" "=========================================="
log_message "INFO" "Starting deployment for ${PROJECT_NAME}"
log_message "INFO" "Branch: ${BRANCH}"
log_message "INFO" "Project path: ${PROJECT_PATH}"
log_message "INFO" "=========================================="

# If project directory does not exist, clone it
if [ ! -d "$PROJECT_PATH" ]; then
    log_message "INFO" "Project directory does not exist. Cloning from GitHub..."

    if git clone "git@github.com:UmanetAlexandru/${PROJECT_NAME}.git" "$PROJECT_PATH" 2>&1 | tee -a "$DEPLOY_LOG"; then
        log_message "INFO" "Repository cloned successfully"
    else
        log_message "ERROR" "Failed to clone repository"
        exit 1
    fi
fi

# Begin deployment
{
    log_message "INFO" "Changing to project directory: ${PROJECT_PATH}"
    cd "$PROJECT_PATH"

    log_message "INFO" "Fetching all updates from remote repository..."
    if ! git fetch --all; then
        log_message "ERROR" "Failed to fetch from remote repository"
        exit 1
    fi

    log_message "INFO" "Resetting local changes and pulling latest from origin/${BRANCH}..."
    if ! git reset --hard "origin/${BRANCH}"; then
        log_message "ERROR" "Failed to reset to origin/${BRANCH}"
        exit 1
    fi

    log_message "INFO" "Current commit: $(git rev-parse --short HEAD) - $(git log -1 --pretty=%B | head -n 1)"

    # Check if docker-compose.yml or compose.yml exists
    if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
        log_message "INFO" "Docker Compose file found. Building and starting containers..."

        log_message "INFO" "Stopping existing containers..."
        ${DOCKER_COMPOSE_CMD} down --remove-orphans 2>&1 | tee -a "$DEPLOY_LOG"

        log_message "INFO" "Building and starting containers..."
        if ${DOCKER_COMPOSE_CMD} up -d --build --force-recreate 2>&1 | tee -a "$DEPLOY_LOG"; then
            log_message "INFO" "Docker containers started successfully"
        else
            log_message "ERROR" "Failed to start Docker containers"
            exit 1
        fi

        # Show running containers
        log_message "INFO" "Running containers:"
        ${DOCKER_COMPOSE_CMD} ps 2>&1 | tee -a "$DEPLOY_LOG"
    else
        log_message "WARN" "No docker-compose.yml or compose.yml found. Skipping Docker deployment."
    fi

    log_message "INFO" "=========================================="
    log_message "INFO" "Deployment completed successfully for ${PROJECT_NAME}"
    log_message "INFO" "=========================================="

} 2>&1 | tee -a "$DEPLOY_LOG"

# Check if deployment was successful
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log_message "ERROR" "Deployment failed for ${PROJECT_NAME}. Check ${DEPLOY_LOG} for details."
    exit 1
fi

log_message "INFO" "Successfully deployed ${PROJECT_NAME} on branch ${BRANCH}"