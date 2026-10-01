#!/bin/bash
# update_epl_matches.sh - Fetch and update EPL matches in SQLite database

API_TOKEN="acb443dbb70c4852b1958b034cdafac6"
DB_FILE="$HOME/Desktop/epl/epl_data.db"
DATE_TO=$(date +%Y-%m-%d)
DATE_FROM=$(date -v-7d +%Y-%m-%d)

# Fetch matches from API
API_RESPONSE=$(curl -s -H "X-Auth-Token: $API_TOKEN" \
  "https://api.football-data.org/v4/matches?competitions=PL&dateFrom=$DATE_FROM&dateTo=$DATE_TO&status=FINISHED")

# Check if we got data
if echo "$API_RESPONSE" | grep -q '"count":0'; then
    echo "No matches found in this date range."
    exit 0
fi

# Parse JSON and create SQL statements
echo "Parsing match data..."

# Process each match using jq if available
if command -v jq &> /dev/null; then
    echo "$API_RESPONSE" | jq -r '.matches[] | @base64' | while read match_data; do
        # Decode base64 and extract fields
        MATCH_JSON=$(echo "$match_data" | base64 --decode)
        
        # Extract match details with proper null handling
        ID=$(echo "$MATCH_JSON" | jq -r '.id')
        SEASON=$(echo "$MATCH_JSON" | jq -r '.season.id')  # Use season.id instead of startDate
        MATCHDAY=$(echo "$MATCH_JSON" | jq -r '.matchday // 0')
        HOME_TEAM_ID=$(echo "$MATCH_JSON" | jq -r '.homeTeam.id')
        AWAY_TEAM_ID=$(echo "$MATCH_JSON" | jq -r '.awayTeam.id')
        
        # Handle referee - get first referee ID or NULL
        REFEREE=$(echo "$MATCH_JSON" | jq -r '.referees[0].id // empty')
        if [ -z "$REFEREE" ]; then
            REFEREE_ID="NULL"
        else
            REFEREE_ID="$REFEREE"
        fi
        
        MATCH_DATE=$(echo "$MATCH_JSON" | jq -r '.utcDate[0:10]')
        STATUS=$(echo "$MATCH_JSON" | jq -r '.status')
        
        # Handle score values that might be null
        HOME_SCORE=$(echo "$MATCH_JSON" | jq -r '.score.fullTime.home // 0')
        AWAY_SCORE=$(echo "$MATCH_JSON" | jq -r '.score.fullTime.away // 0')
        HALF_HOME=$(echo "$MATCH_JSON" | jq -r '.score.halfTime.home // 0')
        HALF_AWAY=$(echo "$MATCH_JSON" | jq -r '.score.halfTime.away // 0')
        
        # Handle venue - escape single quotes for SQL
        VENUE_RAW=$(echo "$MATCH_JSON" | jq -r '.venue // empty')
        if [ -z "$VENUE_RAW" ]; then
            VENUE="NULL"
        else
            # Escape single quotes for SQL
            VENUE=$(echo "$VENUE_RAW" | sed "s/'/''/g")
            VENUE="'$VENUE'"
        fi
        
        LAST_UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
        CREATED_AT=$LAST_UPDATED
        
        # Create SQL INSERT with ON CONFLICT UPDATE
        SQL="INSERT INTO matches (
            id, season_id, matchday, home_team_id, away_team_id, referee_id,
            match_date, status, home_score, away_score, half_time_home_score,
            half_time_away_score, venue, last_updated, created_at
        ) VALUES (
            $ID, $SEASON, $MATCHDAY, $HOME_TEAM_ID, $AWAY_TEAM_ID, $REFEREE_ID,
            '$MATCH_DATE', '$STATUS', $HOME_SCORE, $AWAY_SCORE, $HALF_HOME,
            $HALF_AWAY, $VENUE, '$LAST_UPDATED', '$CREATED_AT'
        ) ON CONFLICT(id) DO UPDATE SET
            season_id = excluded.season_id,
            matchday = excluded.matchday,
            home_team_id = excluded.home_team_id,
            away_team_id = excluded.away_team_id,
            referee_id = excluded.referee_id,
            match_date = excluded.match_date,
            status = excluded.status,
            home_score = excluded.home_score,
            away_score = excluded.away_score,
            half_time_home_score = excluded.half_time_home_score,
            half_time_away_score = excluded.half_time_away_score,
            venue = excluded.venue,
            last_updated = excluded.last_updated;"
        
        # Execute SQL
        echo "$SQL" | sqlite3 "$DB_FILE"
        
        echo "Processed match $ID: $HOME_TEAM_ID vs $AWAY_TEAM_ID ($HOME_SCORE-$AWAY_SCORE)"
    done
else
    # Fallback without jq - use grep/sed (less reliable)
    echo "jq not found. Using basic parsing..."
    
    # Extract match count
    COUNT=$(echo "$API_RESPONSE" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
    echo "Found $COUNT matches"
    
    # Simple processing for demonstration
    echo "Please install jq for better parsing: brew install jq"
    echo "Here's the raw data to inspect:"
    echo "$API_RESPONSE" | head -100
fi

echo "Database update complete!"
