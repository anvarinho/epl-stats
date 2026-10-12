#!/usr/bin/env bash
# Fetch the last seven days, including the full Friday–Monday match window.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./config.sh

check_dependencies
command -v flock >/dev/null || { log_error "Missing dependency: flock"; exit 1; }

# Keep manual runs and the timer from importing concurrently.
exec 9>"${DB_FILE}.weekly.lock"
if ! flock -n 9; then
    log_info "A weekly import is already running"
    exit 0
fi

# Safe for both new and existing databases; never prompts or drops data.
sqlite3 "$DB_FILE" < schema.sql

# Use UK dates to keep the window aligned with Premier League match dates.
date_to=$(TZ=Europe/London date +%F)
date_from=$(TZ=Europe/London date -d "$date_to -7 days" +%F)
exec bash ./collect_data.sh range "$date_from" "$date_to"
