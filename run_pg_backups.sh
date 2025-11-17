#!/bin/bash

# ========================
# PostgreSQL Backup Script
# ========================

BACKUP_DIR="/home/rjprisoris/Laboratory Exercises/Lab8"
DB_NAME="production_db"
DB_USER="postgres"
LOG_FILE="$BACKUP_DIR/pg_backup.log"
BACKUP_FAILED=0

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Ensure backup directories exist
mkdir -p "$BACKUP_DIR"
PHYSICAL_DIR="$BACKUP_DIR/pg_base_backup"
mkdir -p "$PHYSICAL_DIR"

# ------------------------
# Logical Backup
# ------------------------
LOGICAL_BACKUP_FILE="$BACKUP_DIR/production_db_$(date '+%Y-%m-%d-%H%M%S').dump"
log_message "Starting logical backup..."
if pg_dump -U "$DB_USER" -F c "$DB_NAME" -f "$LOGICAL_BACKUP_FILE"; then
    log_message "Logical backup completed: $LOGICAL_BACKUP_FILE"
else
    log_message "Logical backup FAILED"
    BACKUP_FAILED=1
fi

PHYSICAL_DIR="$BACKUP_DIR/pg_base_backup_$(date '+%Y-%m-%d-%H%M%S')"  # unique folder
mkdir -p "$PHYSICAL_DIR"

PHYSICAL_BACKUP_FILE="$PHYSICAL_DIR/pg_base_backup_$(date '+%Y-%m-%d-%H%M%S').tar.gz"
log_message "Starting physical backup..."
if pg_basebackup -U "$DB_USER" -D "$PHYSICAL_DIR" -Ft -z -X stream; then
    log_message "Physical backup completed: $PHYSICAL_BACKUP_FILE"
else
    log_message "Physical backup FAILED"
    BACKUP_FAILED=1
fi
# ------------------------
# Upload to Google Drive (only if backups succeeded)
# ------------------------
if [ "$BACKUP_FAILED" -eq 0 ]; then
    log_message "Uploading backups to Google Drive..."

    # Temporary folder to hold files for upload
    UPLOAD_DIR="$BACKUP_DIR/tmp_upload_$(date '+%Y-%m-%d-%H%M%S')"
    mkdir -p "$UPLOAD_DIR"

    # Copy logical and physical backups into temp folder
    cp "$LOGICAL_BACKUP_FILE" "$UPLOAD_DIR/"
    cp -r "$PHYSICAL_DIR"/* "$UPLOAD_DIR/"

    # Upload temp folder
    if rclone copy "$UPLOAD_DIR" gdrive_backups:; then
        log_message "SUCCESS: Backups uploaded to Google Drive."

        # ---- Add email for success ----
        EMAIL_SUBJECT="SUCCESS: PostgreSQL Backup and Upload"
        EMAIL_BODY="Successfully created and uploaded:\n$(basename "$LOGICAL_BACKUP_FILE") and $(basename "$PHYSICAL_BACKUP_FILE")"
        echo -e "$EMAIL_BODY" | mailx -s "$EMAIL_SUBJECT" roberto.prisoris12@gmail.com

    else
        log_message "FAILURE: Backup upload to Google Drive failed."

        # ---- Add email for failure ----
        EMAIL_SUBJECT="FAILURE: PostgreSQL Backup Upload"
        EMAIL_BODY="Backups were created locally but failed to upload to Google Drive. Check rclone logs.\nCreated files:\n$(basename "$LOGICAL_BACKUP_FILE") and $(basename "$PHYSICAL_BACKUP_FILE")"
        echo -e "$EMAIL_BODY" | mailx -s "$EMAIL_SUBJECT" roberto.prisoris12@gmail.com

        exit 1
    fi

    # Cleanup temporary upload folder
    rm -rf "$UPLOAD_DIR"
else
    log_message "Backup failed, skipping upload."
    exit 1
fi

# ------------------------
# Cleanup (older than 7 days)
# ------------------------
find "$BACKUP_DIR" -type f -name "*.dump" -mtime +7 -exec rm {} \;
find "$PHYSICAL_DIR" -type f -name "*.tar.gz" -mtime +7 -exec rm {} \;

log_message "Backup script finished."
