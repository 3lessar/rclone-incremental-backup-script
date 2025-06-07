#!/bin/bash

# --- Settings ---
SOURCE_DIR="/your/source/directory"
RCLONE_REMOTE_NAME="your-rclone-remote-name"

# Path for current/active backup
REMOTE_CURRENT_BACKUP_PATH="${RCLONE_REMOTE_NAME}:/your-folder-on-cloud"

# Base path for dated archives
REMOTE_ARCHIVE_BASE_DIR="${RCLONE_REMOTE_NAME}:/your-archive-folder-on-cloud"

# Archive path for today, organized by date (e.g., /2025/06/07)
DATE_PATH=$(date +%Y/%m/%d)
REMOTE_ARCHIVE_PATH="${REMOTE_ARCHIVE_BASE_DIR}/${DATE_PATH}" # Used for --backup-dir

# Log file for operations
LOG_FILE="/var/log/rclone_incremental_backup.log"

# Suffix to be added to files when archived by --backup-dir
DATE_SUFFIX_FOR_ARCHIVE=".archived_$(date +"%Y-%m-%d_%H-%M-%S")"

# --- Email Settings for Error Notification ---
ENABLE_ERROR_EMAIL_NOTIFICATION=true
ERROR_RECIPIENT_EMAIL="your_error_email@example.com"

# --- Email Settings for Summary Report ---
ENABLE_SUMMARY_EMAIL_REPORT=true
SUMMARY_RECIPIENT_EMAIL="your_summary_email@example.com"

# --- Ensure the log directory exists ---
mkdir -p "$(dirname "$LOG_FILE")"

# --- Start backup process ---
echo "--------------------------------------------------------------------" >> "$LOG_FILE"
echo "Starting incremental backup with rclone at: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "Source Directory: ${SOURCE_DIR}" >> "$LOG_FILE"
echo "Main Backup Destination (Current): ${REMOTE_CURRENT_BACKUP_PATH}" >> "$LOG_FILE"
echo "Today's Archive Path (for --backup-dir): ${REMOTE_ARCHIVE_PATH}" >> "$LOG_FILE"
echo "Log File: ${LOG_FILE}" >> "$LOG_FILE"

echo "Executing rclone sync command..." >> "$LOG_FILE"
START_TIME_SYNC_SECONDS=$(date +%s)

rclone sync "${SOURCE_DIR}" "${REMOTE_CURRENT_BACKUP_PATH}" \
    --backup-dir "${REMOTE_ARCHIVE_PATH}" \
    --suffix "${DATE_SUFFIX_FOR_ARCHIVE}" \
    --create-empty-src-dirs \
    --transfers 2 \
    --checkers 4 \
    --timeout 300s \
    --contimeout 60s \
    --retries 5 \
    --low-level-retries 10 \
    --log-file="${LOG_FILE}" \
    --stats 1m \
    -v

RCLONE_EXIT_CODE=$?
END_TIME_SYNC_SECONDS=$(date +%s)

if [ ${RCLONE_EXIT_CODE} -eq 0 ]; then
    echo "rclone sync operation completed successfully at $(date '+%Y-%m-%d %H:%M:%S')." | tee -a "$LOG_FILE"

    # --- Collect size and file count stats for summary ---
    BACKUP_STATS=$(rclone size "${REMOTE_CURRENT_BACKUP_PATH}" --human-readable)
    ARCHIVE_STATS=$(rclone size "${REMOTE_ARCHIVE_PATH}" --human-readable)

    # --- Delete old daily archive folders ---
    DAYS_TO_RETAIN_SETS=7
    OLD_ARCHIVE_DATE_TO_DELETE=$(date -d "${DAYS_TO_RETAIN_SETS} days ago" +%Y/%m/%d)
    ARCHIVE_DIR_TO_PURGE="${REMOTE_ARCHIVE_BASE_DIR}/${OLD_ARCHIVE_DATE_TO_DELETE}"

    echo "Attempting to purge old daily archive set: ${ARCHIVE_DIR_TO_PURGE} (retaining last ${DAYS_TO_RETAIN_SETS} days)" >> "$LOG_FILE"
    rclone purge "${ARCHIVE_DIR_TO_PURGE}" -v --log-file="${LOG_FILE}"

    PURGE_EXIT_CODE=$?
    if [ ${PURGE_EXIT_CODE} -eq 0 ]; then
        echo "Purge operation for ${ARCHIVE_DIR_TO_PURGE} completed. This may mean successful purge or that the directory did not exist." >> "$LOG_FILE"
    else
        echo "Error (code: ${PURGE_EXIT_CODE}) during purge of old archive set: ${ARCHIVE_DIR_TO_PURGE}. Check rclone logs." >> "$LOG_FILE"
    fi
else
    # rclone sync failed
    ERROR_MESSAGE_LOG="ERROR: rclone sync operation failed with exit code ${RCLONE_EXIT_CODE} at $(date '+%Y-%m-%d %H:%M:%S'). Please check the log file: ${LOG_FILE}"
    echo "${ERROR_MESSAGE_LOG}" | tee -a "$LOG_FILE"

    if [ "$ENABLE_ERROR_EMAIL_NOTIFICATION" = true ]; then
        EMAIL_SUBJECT_ERROR="[Backup ERROR] rclone sync failed on server $(hostname)"
        EMAIL_BODY_ERROR="The rclone sync backup script encountered an error on server: $(hostname)
Date: $(date '+%Y-%m-%d %H:%M:%S')

Source Directory: ${SOURCE_DIR}
Main Backup Destination: ${REMOTE_CURRENT_BACKUP_PATH}
Today's Archive Path: ${REMOTE_ARCHIVE_PATH}
Rclone Exit Code: ${RCLONE_EXIT_CODE}
Log File: ${LOG_FILE}

Last 20 lines of the log file:
----------------------------------------------------
$(tail -n 20 "$LOG_FILE")
----------------------------------------------------"

        if command -v mail &> /dev/null; then
            echo -e "$EMAIL_BODY_ERROR" | mail -s "$EMAIL_SUBJECT_ERROR" "$ERROR_RECIPIENT_EMAIL"
            echo "Error notification email sent to ${ERROR_RECIPIENT_EMAIL}." >> "$LOG_FILE"
        else
            echo "mail command not found. Cannot send error email notification. Please install mailutils or a similar package." >> "$LOG_FILE"
        fi
    fi
fi

# --- Prepare Summary Output ---
SYNC_DURATION_FORMATTED="N/A"
if [ -n "$START_TIME_SYNC_SECONDS" ] && [ -n "$END_TIME_SYNC_SECONDS" ]; then
    SYNC_DURATION_SECONDS=$((END_TIME_SYNC_SECONDS - START_TIME_SYNC_SECONDS))
    H_DUR=$((SYNC_DURATION_SECONDS / 3600))
    M_DUR=$(((SYNC_DURATION_SECONDS % 3600) / 60))
    S_DUR=$((SYNC_DURATION_SECONDS % 60))
    SYNC_DURATION_FORMATTED=$(printf "%02dh %02dm %02ds" $H_DUR $M_DUR $S_DUR)
fi

STATUS_MESSAGE="SUCCESS"
if [ ${RCLONE_EXIT_CODE} -ne 0 ]; then
    STATUS_MESSAGE="FAILED (Exit Code: ${RCLONE_EXIT_CODE})"
fi

SUMMARY_TITLE="Backup Summary (Finished at: $(date '+%Y-%m-%d %H:%M:%S'))"
SUMMARY_SEPARATOR="--------------------------------------------------------------------"

SUMMARY_CONTENT=$(cat <<EOF
${SUMMARY_SEPARATOR}
${SUMMARY_TITLE}
Source Directory       : ${SOURCE_DIR}
Main Backup Target     : ${REMOTE_CURRENT_BACKUP_PATH}
Today's Archive Path   : ${REMOTE_ARCHIVE_PATH} (Changed/deleted files from main target are moved here)
Base Archive Path      : ${REMOTE_ARCHIVE_BASE_DIR} (Daily archives are kept here)
Log File               : ${LOG_FILE}
Sync Duration          : ${SYNC_DURATION_FORMATTED}
Rclone Sync Status     : ${STATUS_MESSAGE}

Backup Target Stats    :
${BACKUP_STATS}

Today's Archive Stats  :
${ARCHIVE_STATS}
${SUMMARY_SEPARATOR}
EOF
)

# Print summary to standard output
echo "$SUMMARY_CONTENT"

# Append summary to the main log file
echo "$SUMMARY_CONTENT" >> "$LOG_FILE"

# --- Send Summary Email Report ---
if [ "$ENABLE_SUMMARY_EMAIL_REPORT" = true ]; then
    SUMMARY_EMAIL_SUBJECT="[Backup Report] Sync Summary for $(hostname) - Status: ${STATUS_MESSAGE}"

    if command -v mail &> /dev/null; then
        echo "$SUMMARY_CONTENT" | mail -s "$SUMMARY_EMAIL_SUBJECT" "$SUMMARY_RECIPIENT_EMAIL"
        echo "Summary report email sent to ${SUMMARY_RECIPIENT_EMAIL}." >> "$LOG_FILE"
    else
        echo "mail command not found. Cannot send summary report email. Please install mailutils or a similar package." >> "$LOG_FILE"
    fi
fi

exit ${RCLONE_EXIT_CODE}
