# Rclone Incremental Backup Script with Dated Archives and Email Notifications

This Bash script automates daily incremental backups of a source directory to a cloud storage remote using `rclone`. It maintains a "live" mirror of the source and archives any changed or deleted files into daily versioned folders, providing a robust point-in-time recovery solution.

## Features

-   **Incremental Backups:** Uses `rclone sync` to only transfer changed files, saving bandwidth and time.
-   **Dated Versioning/Archiving:** Instead of overwriting or deleting old files, it moves changed/deleted files to a daily-dated archive folder (e.g., `.../archive/2025/06/07/`), preserving file history.
-   **Directory Structure Preservation:** The original directory structure is maintained within the archive folders, making restores simple and intuitive.
-   **Automatic Cleanup:** Automatically purges old daily archive folders after a configurable number of days to manage storage space.
-   **Email Notifications:**
    -   Sends an immediate email alert if the backup operation fails.
    -   Sends a daily summary report email after every run (successful or failed) with detailed stats.
-   **Detailed Logging:** Keeps a comprehensive log file of all operations.
-   **Performance Tuning:** Includes flags for tuning `rclone` performance (transfers, checkers, retries, etc.).

## Prerequisites

Before using this script, ensure the following are installed and configured on your server (tested on Ubuntu):

1.  **[rclone](https://rclone.org/install/):** The core tool for cloud synchronization. You must have it installed and configured with a remote (e.g., for MEGA, Google Drive, Dropbox, etc.).
2.  **[mailutils](https://www.gnu.org/software/mailutils/):** Required for sending email notifications. Install it with:
    ```bash
    sudo apt update && sudo apt install mailutils
    ```
3.  **A Configured Mail Transfer Agent (MTA):** Your server needs to be able to send emails. For reliable delivery to external addresses (like Gmail), it's highly recommended to configure a local MTA (like Postfix) or a nullmailer (like `ssmtp` or `msmtp`) to relay mail through an external SMTP provider (e.g., Gmail, SendGrid).

## Setup and Configuration

1.  **Save the Script:** Save the script content to a file on your server, for example, `rclone_backup.sh`.

2.  **Make it Executable:**
    ```bash
    chmod +x incremental-backup.sh
    ```

3.  **Configure Script Variables:** Open `rclone_backup.sh` with a text editor and configure the settings at the top of the file:

    -   `SOURCE_DIR`: The absolute path to the local directory you want to back up.
    -   `RCLONE_REMOTE_NAME`: The name of your configured `rclone` remote (e.g., `MyMega`, `GDrive`).
    -   `REMOTE_CURRENT_BACKUP_PATH`: The main directory on your cloud remote where the live mirror will be stored.
    -   `REMOTE_ARCHIVE_BASE_DIR`: The base directory on your cloud remote where the daily archive folders will be created.
    -   `LOG_FILE`: The path to the log file. The default `/var/log/rclone_incremental_backup.log` is usually fine.
    -   `ENABLE_ERROR_EMAIL_NOTIFICATION`: Set to `true` to receive emails on failure.
    -   `ERROR_RECIPIENT_EMAIL`: The email address for error notifications.
    -   `ENABLE_SUMMARY_EMAIL_REPORT`: Set to `true` to receive a summary report after every run.
    -   `SUMMARY_RECIPIENT_EMAIL`: The email address for summary reports.

4.  **Configure Other Parameters (Optional):**
    -   `DAYS_TO_RETAIN_SETS`: Inside the script, you can change this value (default is `7`) to control how many days of archives are kept.
    -   `rclone` flags: You can tune performance by adjusting flags like `--transfers`, `--checkers`, etc., in the `rclone sync` command based on your server's resources and your remote's limitations.

## Usage

### Manual Execution

You can run the script manually at any time to test it:
```bash
./incremental-backup.sh
```

### Automated Daily Execution with Cron

For automated daily backups, add the script to your crontab.

1.  Open the crontab for editing:
    ```bash
    crontab -e
    ```

2.  Add a line to schedule the script. For example, to run it every day at 3:15 AM:
    ```cron
    15 3 * * * /path/to/your/rclone_backup.sh >/dev/null 2>&1
    ```
    -   Replace `/path/to/your/rclone_backup.sh` with the absolute path to your script.
    -   `>/dev/null 2>&1` prevents cron from sending its own emails, as our script has its own notification system. The script's log file will contain all necessary details.

## How It Works

1.  **Sync:** The script calls `rclone sync`. `rclone` compares the `SOURCE_DIR` with the `REMOTE_CURRENT_BACKUP_PATH`.
2.  **Archive (`--backup-dir`):**
    -   If a file in the destination (`REMOTE_CURRENT_BACKUP_PATH`) is missing from the source (deleted) or is different (modified), `rclone` moves it to the `REMOTE_ARCHIVE_PATH` (e.g., `.../archive/2025/06/07/`).
    -   This move preserves the original directory structure, making restores easy.
    -   The archived file gets a timestamp suffix.
3.  **Update:** New or modified files from the source are then copied to the destination, ensuring it's an up-to-date mirror.
4.  **Cleanup:** After a successful sync, the script runs `rclone purge` to delete the entire daily archive folder that is older than the `DAYS_TO_RETAIN_SETS` period.
5.  **Reporting:** At the end, a summary is generated and emailed, providing stats on backup size, archive size, duration, and status.

## License

This script is released under the [MIT License](https://opensource.org/licenses/MIT). Feel free to use, modify, and distribute it.
