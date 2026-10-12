## Initial Setup:

# Make all scripts executable

chmod +x \*.sh

# Initialize the database

make init

# Or manually:

./init_db.sh

## Data Collection:

# Backfill historical data (last 5 seasons)

make backfill

# Or manually:

./collect_data.sh backfill

# Daily updates (for cron)

make daily
./collect_data.sh daily

# Specific season

make season YEAR=2023
./collect_data.sh season 2023

## Inspection and Testing:

# View database statistics

make stats
./inspect_db.sh stats

# View team matches

make team NAME="Arsenal"
./inspect_db.sh team "Manchester United"

# View specific season

./inspect_db.sh season 2023

# View database schema

./inspect_db.sh schema

## Automatic weekend results (Linux/systemd)

```bash
make install-weekly
make weekly-status
```

The user timer runs every **Tuesday at 09:00 Asia/Bishkek**, after Monday
evening games in England. It imports the previous seven days through the
current UK date, covering Friday–Monday results and any midweek matches.
Existing matches are refreshed, including corrected scores and statuses.
An empty match window (for example, an international break) is successful.

Missed runs are caught up when the user timer next starts after login/resume.
The machine needs internet access; failures retry twice at 15-minute intervals.
This user timer does not wake a powered-off machine or enable background
execution after logout. A catch-up run fetches the latest seven days, so use
`collect_data.sh range YYYY-MM-DD YYYY-MM-DD` for older gaps after long absences.

Run `make weekly` to fetch immediately, or `make disable-weekly` to stop the
schedule. Data goes to `epl_data.db`, with logs in `epl_etl.log` and the user
journal. The scripts resolve the project directory themselves. Re-run the
installer if you move the checkout. Requires Bash, curl, jq, sqlite3, GNU date,
flock, and a systemd user session. API credentials use `config.sh`.

To change the schedule, edit `systemd/epl-weekend.timer`, run
`make install-weekly`, then `systemctl --user restart epl-weekend.timer`.

## Testing Commands:

# Test API connectivity

curl -s -H "X-Auth-Token: $API_TOKEN" "$API_BASE/competitions/PL" | jq .

# Test database connection

sqlite3 epl_data.db "SELECT name FROM sqlite_master WHERE type='table';"

# Verify data counts

sqlite3 epl*data.db "SELECT COUNT(*) FROM matches; SELECT COUNT(\_) FROM teams;"

# Check recent matches

sqlite3 epl_data.db "SELECT match_date, status FROM matches ORDER BY match_date DESC LIMIT 5;"

## Update

# Show next scheduled game for a team

./inspect_db.sh next "Arsenal"
make next NAME="Manchester United"

# Show upcoming fixtures (default 5)

./inspect_db.sh fixtures "Liverpool"
./inspect_db.sh fixtures "Chelsea" 10 # Show next 10 fixtures
make fixtures NAME="Tottenham"

# Show recent form

./inspect_db.sh form "Manchester City"
./inspect_db.sh form "Newcastle" 8 # Last 8 matches
make form NAME="Arsenal"

# Comprehensive analytics

./inspect_db.sh analytics "Liverpool"
make analytics NAME="Chelsea"

## Head to Head

# Basic head-to-head (last 10 matches)

./inspect_db.sh head2head "Arsenal" "Chelsea"
make head2head TEAM1="Manchester United" TEAM2="Liverpool"

# Custom limit

./inspect_db.sh head2head "Tottenham" "West Ham" 5

# Detailed analysis

./inspect_db.sh h2h "Manchester City" "Arsenal"
make h2h TEAM1="Liverpool" TEAM2="Everton"

# Predict specific match

./inspect_db.sh predict "Arsenal" "Chelsea"
make predict TEAM1="Manchester United" TEAM2="Liverpool"

# Predict all upcoming matches

./inspect_db.sh predictions
make predictions

# Predict specific matchday

./inspect_db.sh predictions 28

# Show table for last season (2023/24)

./epl_table.sh table 2023

# Show detailed table with home/away splits

./epl_table.sh detailed 2022

# Show goal statistics

./epl_table.sh goals 2023

# Show form guide (last 5 matches)

./epl_table.sh form 2023

# Show form guide for last 10 matches

./epl_table.sh form 2023 10

# Show complete season summary

./epl_table.sh summary 2023

# Show all statistics

./epl_table.sh all 2023

# Using make commands

make table SEASON=2023
make epl-stats SEASON=2022
make epl-form SEASON=2023 MATCHES=8

# 1. First, run a diagnostic to see what's missing

chmod +x check_updates.sh
./check_updates.sh

# 2. Force update recent matches (recommended if data is stale)

make force-update DAYS=3

# Or directly:

./collect_data.sh force-update 3

# 3. Fix any missing scores

make fix-scores

# Or:

./collect_data.sh fix-scores

# 4. Run normal daily update

make daily

# 5. Verify the updates worked

make verify-updates

# 6. Check recent matches

./inspect_db.sh stats | grep -A 20 "RECENTLY FINISHED MATCHES"

# Check specific team's recent matches

./inspect_db.sh team "Arsenal"
