#!/usr/bin/env bash
# Read-only health overview for the local Premier League database.
source "$(dirname "$0")/config.sh"

if ! command -v sqlite3 >/dev/null 2>&1; then
    printf 'Error: sqlite3 is required.\n' >&2
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    printf 'Database not found: %s\nRun ./init_db.sh first.\n' "$DB_FILE" >&2
    exit 1
fi

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_MUTED=$'\033[90m'
    C_ACCENT=$'\033[36m'
    C_OK=$'\033[32m'
    C_WARN=$'\033[33m'
else
    C_RESET=''
    C_BOLD=''
    C_MUTED=''
    C_ACCENT=''
    C_OK=''
    C_WARN=''
fi

rule='──────────────────────────────────────────────────────────────────────────────'
title() { printf '\n%s%s%s\n%s\n' "$C_BOLD$C_ACCENT" "$1" "$C_RESET" "$rule"; }
metric() { printf '  %-23s %s\n' "$1" "$2"; }

stats=$(sqlite3 -separator '|' "$DB_FILE" "
SELECT
  (SELECT COUNT(*) FROM matches),
  (SELECT COUNT(*) FROM teams),
  (SELECT COUNT(*) FROM matches WHERE status = 'FINISHED'),
  (SELECT COUNT(*) FROM matches WHERE status IN ('SCHEDULED','TIMED')),
  COALESCE((SELECT MAX(match_date) FROM matches), 'No matches'),
  COALESCE((SELECT strftime('%Y-%m-%d %H:%M', MAX(last_updated)) FROM matches), 'Never'),
  (SELECT COUNT(*) FROM matches WHERE status = 'FINISHED' AND (home_score IS NULL OR away_score IS NULL)),
  (SELECT COUNT(*) FROM matches WHERE status = 'FINISHED' AND home_score = 0 AND away_score = 0),
  (SELECT COUNT(*) FROM matches WHERE date(match_date) BETWEEN date('now','-6 days') AND date('now'));
") || exit 1

IFS='|' read -r match_count team_count finished upcoming latest_match last_sync missing_scores zero_zero week_matches <<< "$stats"

printf '\n%sEPL DATA MONITOR%s\n' "$C_BOLD" "$C_RESET"
printf '%sDatabase: %s%s\n' "$C_MUTED" "$DB_FILE" "$C_RESET"
printf '%sGenerated: %s%s\n' "$C_MUTED" "$(date '+%Y-%m-%d %H:%M %Z')" "$C_RESET"

title 'OVERVIEW'
metric 'Matches tracked' "$match_count"
metric 'Teams' "$team_count"
metric 'Completed' "$finished"
metric 'Upcoming' "$upcoming"
metric 'Matches, last 7 days' "$week_matches"

title 'DATA FRESHNESS'
metric 'Latest match date' "$latest_match"
metric 'Last database update' "$last_sync"

title 'DATA QUALITY'
if [ "${missing_scores:-0}" -eq 0 ]; then
    metric 'Finished matches missing scores' "${C_OK}0  OK${C_RESET}"
else
    metric 'Finished matches missing scores' "${C_WARN}${missing_scores}  REVIEW${C_RESET}"
fi
metric 'Finished 0–0 results' "$zero_zero (valid score; shown for visibility)"

title 'LATEST RESULTS'
sqlite3 -header -column "$DB_FILE" "
SELECT
  m.match_date AS Date,
  ht.tla_code AS Home,
  printf('%d–%d', m.home_score, m.away_score) AS Score,
  at.tla_code AS Away,
  m.matchday AS MD
FROM matches m
JOIN teams ht ON ht.id = m.home_team_id
JOIN teams at ON at.id = m.away_team_id
WHERE m.status = 'FINISHED'
ORDER BY m.match_date DESC, m.id DESC
LIMIT 5;
"

printf '\n%s%s%s\n\n' "$C_MUTED" "$rule" "$C_RESET"
