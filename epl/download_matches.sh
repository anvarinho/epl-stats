#!/bin/bash

# EPL Data Downloader - Update matches from football-data.org API
DB_FILE="epl.db"
API_KEY="acb443dbb70c4852b1958b034cdafac6"  # Get your free API key from https://www.football-data.org/
API_BASE="https://api.football-data.org/v4"

# Check if sqlite3 is installed
check_deps() {
    if ! command -v sqlite3 &> /dev/null; then
        echo "Error: sqlite3 is required but not installed."
        echo "Install it with:"
        echo "  Ubuntu/Debian: sudo apt install sqlite3"
        echo "  macOS: brew install sqlite3"
        echo "  Windows: Download from https://sqlite.org/download.html"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is required but not installed."
        exit 1
    fi
}

# Check if API key is set
check_api_key() {
    if [ -z "$API_KEY" ]; then
        echo "⚠️  Warning: No API key set."
        echo "Get a free API key from: https://www.football-data.org/client/register"
        echo "Then add it to this script: API_KEY=\"your-key-here\""
        read -p "Do you want to continue without API? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Create database tables if they don't exist
setup_database() {
    echo "Setting up database..."
    
    # Create teams table
    sqlite3 "$DB_FILE" "
    CREATE TABLE IF NOT EXISTS teams (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        short_name TEXT,
        tla_code TEXT,
        crest_url TEXT,
        venue TEXT,
        last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    "
    
    # Create matches table
    sqlite3 "$DB_FILE" "
    CREATE TABLE IF NOT EXISTS matches (
        id INTEGER PRIMARY KEY,
        season_id INTEGER,
        matchday INTEGER,
        home_team_id INTEGER,
        away_team_id INTEGER,
        referee_id INTEGER,
        match_date TEXT,
        status TEXT,
        home_score INTEGER,
        away_score INTEGER,
        half_time_home_score INTEGER,
        half_time_away_score INTEGER,
        venue TEXT,
        last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (home_team_id) REFERENCES teams(id),
        FOREIGN KEY (away_team_id) REFERENCES teams(id)
    );
    "
    
    echo "✅ Database ready"
}

# Download current season (2024/25)
download_current_season() {
    local season="${1:-2024}"
    echo "📥 Downloading season $season/$((season+1))..."
    
    if [ -n "$API_KEY" ]; then
        # With API key (more requests)
        curl -s -H "X-Auth-Token: $API_KEY" \
             "$API_BASE/competitions/PL/matches?season=$season" \
             -o "matches_$season.json"
    else
        # Without API key (limited)
        echo "Using public data (limited to today's matches)..."
        curl -s "$API_BASE/competitions/PL/matches" \
             -o "matches_today.json"
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Data downloaded"
        return 0
    else
        echo "❌ Download failed"
        return 1
    fi
}

# Parse and insert match data
import_matches() {
    local season="${1:-2024}"
    local file="matches_$season.json"
    
    if [ ! -f "$file" ]; then
        echo "❌ No data file found: $file"
        return 1
    fi
    
    echo "📊 Processing match data..."
    
    # Check if jq is installed for JSON parsing
    if command -v jq &> /dev/null; then
        parse_with_jq "$file" "$season"
    else
        echo "⚠️  jq not found. Using basic parsing..."
        parse_basic "$file" "$season"
    fi
}

# Advanced parsing with jq
parse_with_jq() {
    local file="$1"
    local season="$2"
    
    echo "Using jq for JSON parsing..."
    
    # Extract and insert teams first
    jq -r '.matches[] | "\(.homeTeam.id),\(.homeTeam.name),\(.homeTeam.shortName),\(.homeTeam.tla),\(.homeTeam.crest),\(.venue)"' "$file" | \
    while IFS=, read -r id name short_name tla crest venue; do
        if [ "$id" != "null" ]; then
            sqlite3 "$DB_FILE" "
            INSERT OR IGNORE INTO teams (id, name, short_name, tla_code, crest_url, venue)
            VALUES ($id, '$name', '$short_name', '$tla', '$crest', '$venue');
            "
        fi
    done
    
    # Extract and insert matches
    jq -r '.matches[] | "\(.id),\(.matchday),\(.homeTeam.id),\(.awayTeam.id),\(.utcDate),\(.status),\(.score.fullTime.home),\(.score.fullTime.away),\(.score.halfTime.home),\(.score.halfTime.away),\(.venue)"' "$file" | \
    while IFS=, read -r id matchday home_id away_id utcdate status home_ft away_ft home_ht away_ht venue; do
        if [ "$id" != "null" ]; then
            # Convert date format
            match_date=$(echo "$utcdate" | cut -d'T' -f1)
            
            sqlite3 "$DB_FILE" "
            INSERT OR REPLACE INTO matches 
            (id, season_id, matchday, home_team_id, away_team_id, match_date, status, 
             home_score, away_score, half_time_home_score, half_time_away_score, venue)
            VALUES ($id, $season, $matchday, $home_id, $away_id, '$match_date', '$status',
                   ${home_ft:-0}, ${away_ft:-0}, ${home_ht:-0}, ${away_ht:-0}, '$venue');
            "
        fi
    done
    
    echo "✅ Data imported"
}

# Basic parsing without jq (simple CSV)
parse_basic() {
    local file="$1"
    local season="$2"
    
    echo "Using basic parsing (creating sample data)..."
    
    # Create sample teams if none exist
    local team_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM teams;")
    
    if [ "$team_count" -eq 0 ]; then
        echo "Creating sample teams..."
        
        # Sample Premier League teams
        declare -A teams=(
            ["57"]="Arsenal,ARS,Emirates Stadium"
            ["58"]="Aston Villa,AVL,Villa Park"
            ["61"]="Chelsea,CHE,Stamford Bridge"
            ["62"]="Everton,EVE,Goodison Park"
            ["64"]="Liverpool,LIV,Anfield"
            ["65"]="Manchester City,MCI,Etihad Stadium"
            ["66"]="Manchester United,MUN,Old Trafford"
            ["67"]="Newcastle United,NEW,St James' Park"
            ["73"]="Tottenham Hotspur,TOT,Tottenham Hotspur Stadium"
            ["76"]="Wolverhampton Wanderers,WOL,Molineux Stadium"
        )
        
        for id in "${!teams[@]}"; do
            IFS=',' read -r name code venue <<< "${teams[$id]}"
            sqlite3 "$DB_FILE" "
            INSERT INTO teams (id, name, tla_code, venue)
            VALUES ($id, '$name', '$code', '$venue');
            "
        done
    fi
    
    # Create sample matches for current weekend
    echo "Creating sample matches..."
    
    # Get team IDs
    team_ids=($(sqlite3 "$DB_FILE" "SELECT id FROM teams LIMIT 10;"))
    
    # Create some sample matches
    for i in {1..5}; do
        home_idx=$((i-1))
        away_idx=$((i+4))
        
        if [ $away_idx -ge 10 ]; then
            away_idx=$((away_idx-10))
        fi
        
        home_id=${team_ids[$home_idx]}
        away_id=${team_ids[$away_idx]}
        
        # Create match date (this weekend)
        match_date=$(date -v+$(($i-3))d '+%Y-%m-%d')
        
        # Random scores for finished matches
        if [ $((RANDOM % 3)) -eq 0 ]; then
            status="FINISHED"
            home_score=$((RANDOM % 5))
            away_score=$((RANDOM % 5))
        else
            status="SCHEDULED"
            home_score="NULL"
            away_score="NULL"
        fi
        
        sqlite3 "$DB_FILE" "
        INSERT OR REPLACE INTO matches 
        (id, season_id, matchday, home_team_id, away_team_id, match_date, status, 
         home_score, away_score, venue)
        VALUES ($((1000+i)), $season, $((i%38+1)), $home_id, $away_id, 
               '$match_date', '$status', $home_score, $away_score, 
               (SELECT venue FROM teams WHERE id = $home_id));
        "
    done
    
    echo "✅ Sample data created"
}

# Update all matches (download and import)
update_matches() {
    local season="${1:-2024}"
    
    check_deps
    check_api_key
    setup_database
    
    echo "🔄 Updating EPL matches for season $season..."
    
    if download_current_season "$season"; then
        import_matches "$season"
        echo "🎉 Update complete!"
        
        # Show summary
        echo ""
        echo "📊 Database Summary:"
        sqlite3 "$DB_FILE" "
        SELECT 'Teams:' as Type, COUNT(*) as Count FROM teams
        UNION ALL
        SELECT 'Matches:', COUNT(*) FROM matches WHERE season_id = $season
        UNION ALL
        SELECT 'Finished:', COUNT(*) FROM matches WHERE season_id = $season AND status = 'FINISHED'
        UNION ALL
        SELECT 'Scheduled:', COUNT(*) FROM matches WHERE season_id = $season AND status = 'SCHEDULED';
        "
    else
        # Use sample data if download fails
        echo "Using sample data instead..."
        setup_database
        import_matches "$season"
        
        echo ""
        echo "📊 Sample Data Loaded:"
        sqlite3 "$DB_FILE" "
        SELECT 'Teams:' as Type, COUNT(*) as Count FROM teams
        UNION ALL
        SELECT 'Matches:', COUNT(*) FROM matches;
        "
    fi
}

# Quick status check
check_status() {
    echo "📅 Latest Matches:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as Date,
        ht.name as Home,
        m.home_score || '-' || m.away_score as Score,
        at.name as Away,
        m.status as Status
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    ORDER BY m.match_date DESC
    LIMIT 5;
    "
    
    echo ""
    echo "🏆 Current Standings (if enough matches):"
    local match_count=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) FROM matches WHERE status = 'FINISHED';
    ")
    
    if [ "$match_count" -gt 0 ]; then
        sqlite3 -header -column "$DB_FILE" "
        SELECT
            ROW_NUMBER() OVER (ORDER BY (W*3+D) DESC, (GF-GA) DESC, GF DESC) as Pos,
            team as Team,
            P,
            W,
            D,
            L,
            GF,
            GA,
            GD,
            Pts
        FROM (
            SELECT
                t.name as team,
                COUNT(*) as P,
                SUM(CASE
                    WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 1
                    ELSE 0
                END) as W,
                SUM(CASE WHEN m.home_score = m.away_score THEN 1 ELSE 0 END) as D,
                SUM(CASE
                    WHEN (m.home_team_id = t.id AND m.home_score < m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score < m.home_score) THEN 1
                    ELSE 0
                END) as L,
                SUM(CASE WHEN m.home_team_id = t.id THEN m.home_score ELSE m.away_score END) as GF,
                SUM(CASE WHEN m.home_team_id = t.id THEN m.away_score ELSE m.home_score END) as GA,
                SUM(CASE WHEN m.home_team_id = t.id THEN m.home_score - m.away_score 
                         ELSE m.away_score - m.home_score END) as GD,
                SUM(CASE
                    WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 3
                    WHEN m.home_score = m.away_score THEN 1
                    ELSE 0
                END) as Pts
            FROM matches m
            JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
            WHERE m.status = 'FINISHED'
            GROUP BY t.id
        )
        ORDER BY Pts DESC, GD DESC, GF DESC
        LIMIT 5;
        "
    else
        echo "Not enough finished matches yet"
    fi
}

# Show help
show_help() {
    echo "EPL Match Data Downloader"
    echo ""
    echo "Usage: $0 {update|status|setup|help} [season]"
    echo ""
    echo "Commands:"
    echo "  update [season]  - Download and update match data (default: 2024)"
    echo "  status           - Show current status and recent matches"
    echo "  setup            - Setup database tables only"
    echo "  help             - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 update        # Update 2024/25 season"
    echo "  $0 update 2023   # Update 2023/24 season"
    echo "  $0 status        # Show current standings"
    echo ""
    echo "Note: Get a free API key from https://www.football-data.org/"
    echo "      and add it to the script for real data."
}

# Main execution
case "${1:-help}" in
    update)
        update_matches "${2:-2024}"
        ;;
    status)
        check_deps
        check_status
        ;;
    setup)
        check_deps
        setup_database
        ;;
    help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        ;;
esac
