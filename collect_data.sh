#!/bin/bash

# Main data collection script for EPL matches (macOS compatible)
source config.sh

# Function to get season years for backfill
get_season_years() {
    local current_year=$(date +"%Y")
    seq $((current_year - 4)) $current_year
}

# Function to insert/update team
insert_team() {
    local team_json="$1"
    local team_id=$(echo "$team_json" | jq -r '.id')
    local team_name=$(echo "$team_json" | jq -r '.name // ""' | sed "s/'/''/g")
    local short_name=$(echo "$team_json" | jq -r '.shortName // ""' | sed "s/'/''/g")
    local tla_code=$(echo "$team_json" | jq -r '.tla // ""')
    local crest_url=$(echo "$team_json" | jq -r '.crest // ""')
    
    sqlite3 "$DB_FILE" <<EOF
INSERT OR REPLACE INTO teams (id, name, short_name, tla_code, crest_url) 
VALUES ($team_id, '$team_name', '$short_name', '$tla_code', '$crest_url');
EOF
}

# Function to insert/update referee
insert_referee() {
    local referee_json="$1"
    local referee_id=$(echo "$referee_json" | jq -r '.id')
    local referee_name=$(echo "$referee_json" | jq -r '.name // ""' | sed "s/'/''/g")
    
    if [ -n "$referee_name" ] && [ "$referee_name" != "null" ]; then
        sqlite3 "$DB_FILE" <<EOF
INSERT OR IGNORE INTO referees (id, name) 
VALUES ($referee_id, '$referee_name');
EOF
    fi
}

# Function to insert/update match
insert_match() {
    local match_json="$1"
    local season_id="$2"
    
    local match_id=$(echo "$match_json" | jq -r '.id')
    local matchday=$(echo "$match_json" | jq -r '.matchday // 0')
    local home_team_id=$(echo "$match_json" | jq -r '.homeTeam.id')
    local away_team_id=$(echo "$match_json" | jq -r '.awayTeam.id')
    
    # Handle referees - check if array exists and has elements
    local referee_id=0
    if echo "$match_json" | jq -e '.referees | length > 0' > /dev/null; then
        referee_id=$(echo "$match_json" | jq -r '.referees[0].id // 0')
    fi
    
    local match_date=$(echo "$match_json" | jq -r '.utcDate' | cut -d'T' -f1)
    local status=$(echo "$match_json" | jq -r '.status')
    
    # Scores (handle null values properly)
    local home_score=$(echo "$match_json" | jq -r '.score.fullTime.home // 0')
    local away_score=$(echo "$match_json" | jq -r '.score.fullTime.away // 0')
    local half_time_home=$(echo "$match_json" | jq -r '.score.halfTime.home // 0')
    local half_time_away=$(echo "$match_json" | jq -r '.score.halfTime.away // 0')
    
    # Convert null to 0 for SQLite
    [ "$home_score" = "null" ] && home_score=0
    [ "$away_score" = "null" ] && away_score=0
    [ "$half_time_home" = "null" ] && half_time_home=0
    [ "$half_time_away" = "null" ] && half_time_away=0
    
    local venue=$(echo "$match_json" | jq -r '.venue // ""' | sed "s/'/''/g")
    
    sqlite3 "$DB_FILE" <<EOF
INSERT OR REPLACE INTO matches (
    id, season_id, matchday, home_team_id, away_team_id, referee_id, 
    match_date, status, home_score, away_score, 
    half_time_home_score, half_time_away_score, venue
) VALUES (
    $match_id, $season_id, $matchday, $home_team_id, $away_team_id, 
    $referee_id, '$match_date', '$status', $home_score, $away_score,
    $half_time_home, $half_time_away, '$venue'
);
EOF
}

# Function to fetch matches for a specific season
fetch_season_matches() {
    local season="$1"
    log_info "Fetching matches for season: $season"
    
    local endpoint="competitions/$COMPETITION_ID/matches?season=$season"
    local response
    response=$(api_call "$endpoint")
    
    local api_result=$?
    
    if [ $api_result -eq 0 ] && [ -n "$response" ]; then
        # Check if response contains matches
        if ! echo "$response" | jq -e '.matches' > /dev/null 2>&1; then
            log_error "Invalid API response format for season $season"
            echo "Response: $response" >> "$LOG_FILE"
            return 1
        fi
        
        local match_count=$(echo "$response" | jq -r '.resultSet.count // 0')
        
        if [ "$match_count" -eq 0 ]; then
            log_warning "No matches found for season $season"
            return 0
        fi
        
        log_info "Processing $match_count matches for season $season"
        
        # Process each match
        local processed=0
        echo "$response" | jq -c '.matches[]' | while read -r match; do
            if [ -n "$match" ] && [ "$match" != "null" ]; then
                # Insert teams first
                local home_team=$(echo "$match" | jq -r '.homeTeam')
                local away_team=$(echo "$match" | jq -r '.awayTeam')
                insert_team "$home_team"
                insert_team "$away_team"
                
                # Insert referee if available
                if echo "$match" | jq -e '.referees | length > 0' > /dev/null; then
                    local referee=$(echo "$match" | jq -r '.referees[0]')
                    insert_referee "$referee"
                fi
                
                # Insert match
                insert_match "$match" "$season"
                processed=$((processed + 1))
            fi
        done
        
        log_success "Completed processing season $season ($processed matches)"
    else
        log_error "Failed to fetch matches for season $season (API result: $api_result)"
        return 1
    fi
}

# Function for daily updates (last 7 days + next 7 days)
# Function for daily updates - IMPROVED VERSION
fetch_daily_updates() {
    log_info "Fetching daily updates"
    
    local today=$(date +"%Y-%m-%d")
    local yesterday=$(date -v-1d -j -f "%Y-%m-%d" "$today" +"%Y-%m-%d" 2>/dev/null || date -d "1 day ago" +"%Y-%m-%d")
    local tomorrow=$(date -v+1d -j -f "%Y-%m-%d" "$today" +"%Y-%m-%d" 2>/dev/null || date -d "1 day" +"%Y-%m-%d")
    
    # Get updates for yesterday, today, and tomorrow to catch all recent activity
    local date_from="$yesterday"
    local date_to="$tomorrow"
    
    local endpoint="competitions/$COMPETITION_ID/matches?dateFrom=$date_from&dateTo=$date_to"
    local response
    response=$(api_call "$endpoint")
    
    local api_result=$?
    
    if [ $api_result -eq 0 ] && [ -n "$response" ]; then
        local match_count=$(echo "$response" | jq -r '.resultSet.count // 0')
        log_info "Processing $match_count matches for date range $date_from to $date_to"
        
        if [ "$match_count" -eq 0 ]; then
            log_warning "No matches found in the date range"
            return 0
        fi
        
        local processed=0
        local updated=0
        local skipped=0
        
        # Process each match
        echo "$response" | jq -c '.matches[]' | while read -r match; do
            if [ -n "$match" ] && [ "$match" != "null" ]; then
                local match_id=$(echo "$match" | jq -r '.id')
                local status=$(echo "$match" | jq -r '.status')
                local season=$(echo "$match" | jq -r '.season.id')
                local match_date=$(echo "$match" | jq -r '.utcDate' | cut -d'T' -f1)
                
                # Check if match already exists and has same status
                local existing_status=$(sqlite3 "$DB_FILE" "SELECT status FROM matches WHERE id = $match_id;" 2>/dev/null)
                
                if [ -n "$existing_status" ]; then
                    # Match exists, check if status changed
                    if [ "$existing_status" = "$status" ] && [ "$status" != "FINISHED" ]; then
                        # Status unchanged and not finished, skip update
                        skipped=$((skipped + 1))
                        continue
                    else
                        # Status changed or match finished, update it
                        updated=$((updated + 1))
                    fi
                else
                    # New match
                    processed=$((processed + 1))
                fi
                
                # Insert teams
                local home_team=$(echo "$match" | jq -r '.homeTeam')
                local away_team=$(echo "$match" | jq -r '.awayTeam')
                insert_team "$home_team"
                insert_team "$away_team"
                
                # Insert referee if available
                if echo "$match" | jq -e '.referees | length > 0' > /dev/null; then
                    local referee=$(echo "$match" | jq -r '.referees[0]')
                    insert_referee "$referee"
                fi
                
                # Insert/update match
                insert_match "$match" "$season"
                
                log_info "Updated match: $match_id - $match_date - $status"
            fi
        done
        
        log_success "Daily updates completed: $processed new, $updated updated, $skipped skipped"
        
        # Also fetch any matches from last 3 days that might have status changes
        update_recent_finished_matches
        
    else
        log_error "Failed to fetch daily updates (API result: $api_result)"
        return 1
    fi
}

# New function to update recent matches that might have finished
update_recent_finished_matches() {
    log_info "Checking for recently finished matches from past 3 days..."
    
    local today=$(date +"%Y-%m-%d")
    local three_days_ago=$(date -v-3d -j -f "%Y-%m-%d" "$today" +"%Y-%m-%d" 2>/dev/null || date -d "3 days ago" +"%Y-%m-%d")
    
    # Get match IDs from database that were scheduled in last 3 days
    local match_ids=$(sqlite3 "$DB_FILE" "
    SELECT m.id 
    FROM matches m
    WHERE m.match_date >= '$three_days_ago' 
      AND m.match_date <= '$today'
      AND m.status IN ('SCHEDULED', 'TIMED', 'IN_PLAY', 'PAUSED')
    LIMIT 20;
    ")
    
    if [ -n "$match_ids" ]; then
        log_info "Found $(echo "$match_ids" | wc -l | tr -d ' ') recent matches to check for status updates"
        
        for match_id in $match_ids; do
            # Fetch individual match details
            local endpoint="matches/$match_id"
            local response
            response=$(api_call "$endpoint")
            
            if [ $? -eq 0 ] && [ -n "$response" ]; then
                local match_json=$(echo "$response" | jq -r '.match // .')
                
                if [ -n "$match_json" ] && [ "$match_json" != "null" ]; then
                    local status=$(echo "$match_json" | jq -r '.status')
                    local season=$(echo "$match_json" | jq -r '.season.id')
                    
                    # Get current status from DB
                    local current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM matches WHERE id = $match_id;" 2>/dev/null)
                    
                    if [ "$current_status" != "$status" ]; then
                        # Status changed, update match
                        local home_team=$(echo "$match_json" | jq -r '.homeTeam')
                        local away_team=$(echo "$match_json" | jq -r '.awayTeam')
                        insert_team "$home_team"
                        insert_team "$away_team"
                        
                        if echo "$match_json" | jq -e '.referees | length > 0' > /dev/null; then
                            local referee=$(echo "$match_json" | jq -r '.referees[0]')
                            insert_referee "$referee"
                        fi
                        
                        insert_match "$match_json" "$season"
                        log_info "Updated match $match_id: $current_status → $status"
                    fi
                    
                    # Small delay to avoid rate limiting
                    sleep 0.5
                fi
            fi
        done
    fi
}

# Function to force update all matches from last N days
force_update_recent_matches() {
    local days="${1:-7}"
    
    log_info "Force updating all matches from last $days days"
    
    local today=$(date +"%Y-%m-%d")
    local days_ago=$(date -v-${days}d -j -f "%Y-%m-%d" "$today" +"%Y-%m-%d" 2>/dev/null || date -d "$days days ago" +"%Y-%m-%d")
    
    local endpoint="competitions/$COMPETITION_ID/matches?dateFrom=$days_ago&dateTo=$today"
    local response
    response=$(api_call "$endpoint")
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        local match_count=$(echo "$response" | jq -r '.resultSet.count // 0')
        log_info "Force updating $match_count matches from $days_ago to $today"
        
        local updated=0
        echo "$response" | jq -c '.matches[]' | while read -r match; do
            if [ -n "$match" ] && [ "$match" != "null" ]; then
                local match_id=$(echo "$match" | jq -r '.id')
                local season=$(echo "$match" | jq -r '.season.id')
                
                # Insert teams
                local home_team=$(echo "$match" | jq -r '.homeTeam')
                local away_team=$(echo "$match" | jq -r '.awayTeam')
                insert_team "$home_team"
                insert_team "$away_team"
                
                # Insert referee if available
                if echo "$match" | jq -e '.referees | length > 0' > /dev/null; then
                    local referee=$(echo "$match" | jq -r '.referees[0]')
                    insert_referee "$referee"
                fi
                
                # Update match (force)
                insert_match "$match" "$season"
                updated=$((updated + 1))
            fi
        done
        
        log_success "Force updated $updated matches"
    else
        log_error "Failed to force update recent matches"
        return 1
    fi
}

# Function to check for missing scores
check_missing_scores() {
    log_info "Checking for matches with missing scores..."
    
    local count=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) 
    FROM matches 
    WHERE status = 'FINISHED' 
      AND (home_score IS NULL OR away_score IS NULL OR home_score = 0 AND away_score = 0);
    ")
    
    if [ "$count" -gt 0 ]; then
        log_warning "Found $count finished matches with missing or 0-0 scores"
        
        # Get match IDs
        local match_ids=$(sqlite3 "$DB_FILE" "
        SELECT id 
        FROM matches 
        WHERE status = 'FINISHED' 
          AND (home_score IS NULL OR away_score IS NULL OR home_score = 0 AND away_score = 0)
        LIMIT 10;
        ")
        
        for match_id in $match_ids; do
            log_info "Fixing scores for match $match_id"
            local endpoint="matches/$match_id"
            local response
            response=$(api_call "$endpoint")
            
            if [ $? -eq 0 ] && [ -n "$response" ]; then
                local match_json=$(echo "$response" | jq -r '.match // .')
                if [ -n "$match_json" ] && [ "$match_json" != "null" ]; then
                    local season=$(echo "$match_json" | jq -r '.season.id')
                    insert_match "$match_json" "$season"
                    log_info "Updated scores for match $match_id"
                fi
            fi
            sleep 0.5
        done
    else
        log_success "No matches with missing scores found"
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    test_api_connection || exit 1
    
    case "${1:-daily}" in
        "backfill")
            log_info "Starting backfill for last 5 seasons"
            for season in $(get_season_years); do
                if fetch_season_matches "$season"; then
                    log_success "Season $season completed successfully"
                else
                    log_error "Season $season failed, but continuing..."
                fi
                sleep 3  # Rate limiting between seasons
            done
            log_success "Backfill completed"
            ;;
        "daily")
            fetch_daily_updates
            check_missing_scores
            ;;
        "force-update")
            force_update_recent_matches "${2:-7}"
            ;;
        "fix-scores")
            check_missing_scores
            ;;
        "season")
            if [ -z "$2" ]; then
                log_error "Please specify a season year"
                exit 1
            fi
            fetch_season_matches "$2"
            ;;
        "test")
            log_info "Testing with a single API call"
            api_call "competitions/$COMPETITION_ID" | jq .
            ;;
        *)
            log_error "Usage: $0 {daily|backfill|season <year>|test}"
            exit 1
            ;;
    esac
fi
