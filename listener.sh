#!/bin/bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to clean old logs
cleanup_old_logs() {
    find "$LOG_DIR" -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S'): INFO - Cleaned logs older than ${LOG_RETENTION_DAYS} days" >> "$LISTENER_LOG"
}

# Function to log messages
log_message() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ${level} - $*" | tee -a "$LISTENER_LOG"
}

# Cleanup old logs on startup
cleanup_old_logs

log_message "INFO" "GitHub Webhook Listener starting on port ${WEBHOOK_PORT}..."
log_message "INFO" "Projects base directory: ${PROJECTS_BASE_DIR}"
log_message "INFO" "Logs directory: ${LOG_DIR}"

# Start listening on the port
while true; do
    # Clean old logs periodically (every request)
    cleanup_old_logs

    log_message "INFO" "Listening for webhook on port ${WEBHOOK_PORT}..."

    # Listen for incoming webhook
    REQUEST=$(echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 23\r\n\r\n{\"status\":\"received\"}" | nc -l -p $WEBHOOK_PORT)

    # Extract POST data from request
    POST_DATA=$(echo "$REQUEST" | sed -n '/^\r$/,$p' | tail -n +2)

    # Check if POST_DATA is empty
    if [ -z "$POST_DATA" ]; then
        log_message "WARN" "Received empty webhook payload"
        continue
    fi

    # Parse webhook data
    PROJECT_NAME=$(echo "$POST_DATA" | jq -r '.repository.full_name | split("/") | last' 2>/dev/null || echo "")
    BRANCH_NAME=$(echo "$POST_DATA" | jq -r '.ref | split("/") | last' 2>/dev/null || echo "")

    # Validate parsed data
    if [ -z "$PROJECT_NAME" ] || [ "$PROJECT_NAME" == "null" ]; then
        log_message "WARN" "Could not parse project name from webhook"
        continue
    fi

    if [ -z "$BRANCH_NAME" ] || [ "$BRANCH_NAME" == "null" ]; then
        log_message "WARN" "Could not parse branch name from webhook"
        continue
    fi

    log_message "INFO" "Received webhook - Project: ${PROJECT_NAME}, Branch: ${BRANCH_NAME}"

    # Only deploy if branch matches default branch
    if [ "$BRANCH_NAME" == "$DEFAULT_BRANCH" ]; then
        log_message "INFO" "Triggering deployment for ${PROJECT_NAME} on branch ${BRANCH_NAME}"

        # Run deployment script in background
        "${SCRIPT_DIR}/deploy.sh" "$PROJECT_NAME" "$BRANCH_NAME" &

        log_message "INFO" "Deployment script started for ${PROJECT_NAME}"
    else
        log_message "INFO" "Ignored push to branch '${BRANCH_NAME}' (only ${DEFAULT_BRANCH} is auto-deployed)"
    fi
done
