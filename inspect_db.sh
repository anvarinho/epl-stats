#!/bin/bash

# Database inspection and query utilities
source config.sh

show_stats() {
    log_info "Database Statistics for $DB_FILE"
    
    echo
    echo "=== DATABASE OVERVIEW ==="
    sqlite3 "$DB_FILE" "
    SELECT 
        (SELECT COUNT(*) FROM seasons) as season_count,
        (SELECT COUNT(*) FROM teams) as team_count,
        (SELECT COUNT(*) FROM referees) as referee_count,
        (SELECT COUNT(*) FROM matches) as match_count;
    " | awk -F'|' '{
        printf "Seasons: %d\nTeams: %d\nReferees: %d\nMatches: %d\n", $1, $2, $3, $4
    }'
    
    echo
    echo "=== MATCHES BY SEASON ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT s.id as season, COUNT(m.id) as match_count
    FROM seasons s
    LEFT JOIN matches m ON s.id = m.season_id
    GROUP BY s.id
    ORDER BY s.id DESC;
    "
    
    echo
    echo "=== MATCHES BY STATUS ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT status, COUNT(*) as count
    FROM matches
    GROUP BY status
    ORDER BY count DESC;
    "

    echo
    echo "=== RECENTLY FINISHED MATCHES ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        ht.name as home_team,
        m.home_score,
        m.away_score,
        at.name as away_team,
        m.status
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.status IN ('FINISHED', 'FT')  -- Filter for completed matches
    ORDER BY m.match_date DESC
    LIMIT 10;
    "

    echo
    echo "=== RECENTLY FINISHED MATCHES ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        m.matchday,
        ht.name as home_team,
        m.home_score || ' - ' || m.away_score as score,
        at.name as away_team
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.status = 'FINISHED'
    ORDER BY m.match_date DESC
    LIMIT 10;
    "
}

show_team_matches() {
    local team_name="$1"
    if [ -z "$team_name" ]; then
        log_error "Please provide a team name"
        return 1
    fi
    
    log_info "Showing matches for: $team_name"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        ht.name as home_team,
        m.home_score,
        m.away_score,
        at.name as away_team,
        m.status
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%'
    ORDER BY m.match_date DESC
    LIMIT 15;
    "
}

show_season_matches() {
    local season="$1"
    if [ -z "$season" ]; then
        season=$(date +"%Y")
    fi
    
    log_info "Showing matches for season: $season"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.matchday,
        m.match_date as date,
        ht.name as home_team,
        m.home_score,
        m.away_score,
        at.name as away_team,
        m.status
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.season_id = $season
    ORDER BY m.matchday, m.match_date
    LIMIT 20;
    "
}


show_next_game() {
    local team_name="$1"
    if [ -z "$team_name" ]; then
        log_error "Please provide a team name"
        return 1
    fi
    
    log_info "Finding next scheduled game for: $team_name"
    
    echo
    echo "=== NEXT SCHEDULED GAME: $team_name ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        m.matchday,
        CASE 
            WHEN ht.name LIKE '%$team_name%' THEN 'HOME'
            WHEN at.name LIKE '%$team_name%' THEN 'AWAY'
        END as venue,
        ht.name as home_team,
        at.name as away_team,
        m.status,
        r.name as referee,
        m.venue as stadium
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    LEFT JOIN referees r ON m.referee_id = r.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT 1;
    "
}

show_upcoming_fixtures() {
    local team_name="$1"
    local limit="${2:-5}"
    
    if [ -z "$team_name" ]; then
        log_error "Please provide a team name"
        return 1
    fi
    
    log_info "Showing next $limit fixtures for: $team_name"
    
    echo
    echo "=== UPCOMING FIXTURES: $team_name (Next $limit) ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        m.matchday,
        CASE 
            WHEN ht.name LIKE '%$team_name%' THEN '🏠 HOME'
            WHEN at.name LIKE '%$team_name%' THEN '✈️ AWAY'
        END as venue,
        ht.name as home_team,
        at.name as away_team,
        m.status,
        r.name as referee
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    LEFT JOIN referees r ON m.referee_id = r.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT $limit;
    "
}

show_team_form() {
    local team_name="$1"
    local limit="${2:-5}"
    
    if [ -z "$team_name" ]; then
        log_error "Please provide a team name"
        return 1
    fi
    
    log_info "Showing recent form for: $team_name"
    
    echo
    echo "=== RECENT FORM: $team_name (Last $limit Matches) ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        m.matchday,
        ht.name as home_team,
        m.home_score || ' - ' || m.away_score as score,
        at.name as away_team,
        CASE 
            WHEN m.home_score > m.away_score AND ht.name LIKE '%$team_name%' THEN '✅ WIN'
            WHEN m.away_score > m.home_score AND at.name LIKE '%$team_name%' THEN '✅ WIN'
            WHEN m.home_score < m.away_score AND ht.name LIKE '%$team_name%' THEN '❌ LOSS'
            WHEN m.away_score < m.home_score AND at.name LIKE '%$team_name%' THEN '❌ LOSS'
            WHEN m.home_score = m.away_score THEN '⚫ DRAW'
            ELSE '❓ UNKNOWN'
        END as result,
        CASE 
            WHEN ht.name LIKE '%$team_name%' THEN '🏠 HOME'
            WHEN at.name LIKE '%$team_name%' THEN '✈️ AWAY'
        END as venue
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status = 'FINISHED'
    ORDER BY m.match_date DESC
    LIMIT $limit;
    "
}

show_team_analytics() {
    local team_name="$1"
    
    if [ -z "$team_name" ]; then
        log_error "Please provide a team name"
        return 1
    fi
    
    log_info "Showing comprehensive analytics for: $team_name"
    
    echo
    echo "=== COMPREHENSIVE ANALYTICS: $team_name ==="
    
    # Basic team info
    echo "📊 TEAM OVERVIEW:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        name,
        short_name,
        tla_code as code
    FROM teams 
    WHERE name LIKE '%$team_name%'
    LIMIT 1;
    "
    
    # Next game details
    echo
    echo "⏰ NEXT SCHEDULED GAME:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        m.matchday,
        CASE 
            WHEN ht.name LIKE '%$team_name%' THEN '🏠 HOME vs ' || at.name
            WHEN at.name LIKE '%$team_name%' THEN '✈️ AWAY @ ' || ht.name
        END as fixture,
        m.venue as stadium,
        r.name as referee
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    LEFT JOIN referees r ON m.referee_id = r.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT 1;
    "
    
    # Season performance
    echo
    echo "📈 CURRENT SEASON PERFORMANCE:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        COUNT(*) as total_matches,
        SUM(CASE 
            WHEN (m.home_score > m.away_score AND ht.name LIKE '%$team_name%') OR 
                 (m.away_score > m.home_score AND at.name LIKE '%$team_name%') THEN 1 
            ELSE 0 
        END) as wins,
        SUM(CASE 
            WHEN m.home_score = m.away_score THEN 1 
            ELSE 0 
        END) as draws,
        SUM(CASE 
            WHEN (m.home_score < m.away_score AND ht.name LIKE '%$team_name%') OR 
                 (m.away_score < m.home_score AND at.name LIKE '%$team_name%') THEN 1 
            ELSE 0 
        END) as losses,
        SUM(CASE 
            WHEN ht.name LIKE '%$team_name%' THEN m.home_score 
            ELSE m.away_score 
        END) as goals_for,
        SUM(CASE 
            WHEN ht.name LIKE '%$team_name%' THEN m.away_score 
            ELSE m.home_score 
        END) as goals_against
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    JOIN seasons s ON m.season_id = s.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status = 'FINISHED'
      AND s.current = 1;
    "
    
    # Upcoming fixtures
    echo
    echo "🗓️ UPCOMING FIXTURES:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        m.matchday,
        CASE 
            WHEN ht.name LIKE '%$team_name%' THEN '🏠 vs ' || at.name
            WHEN at.name LIKE '%$team_name%' THEN '✈️ @ ' || ht.name
        END as fixture
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT 5;
    "
    
    # Recent form (last 5 matches)
    echo
    echo "📊 RECENT FORM (Last 5 Matches):"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        CASE 
            WHEN ht.name LIKE '%$team_name%' THEN '🏠 ' || at.name
            WHEN at.name LIKE '%$team_name%' THEN '✈️ ' || ht.name
        END as opponent,
        m.home_score || ' - ' || m.away_score as score,
        CASE 
            WHEN m.home_score > m.away_score AND ht.name LIKE '%$team_name%' THEN '✅ WIN'
            WHEN m.away_score > m.home_score AND at.name LIKE '%$team_name%' THEN '✅ WIN'
            WHEN m.home_score < m.away_score AND ht.name LIKE '%$team_name%' THEN '❌ LOSS'
            WHEN m.away_score < m.home_score AND at.name LIKE '%$team_name%' THEN '❌ LOSS'
            ELSE '⚫ DRAW'
        END as result
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE (ht.name LIKE '%$team_name%' OR at.name LIKE '%$team_name%')
      AND m.status = 'FINISHED'
    ORDER BY m.match_date DESC
    LIMIT 5;
    "
}

# Head to head
show_head_to_head() {
    local team1="$1"
    local team2="$2"
    local limit="${3:-10}"
    
    if [ -z "$team1" ] || [ -z "$team2" ]; then
        log_error "Please provide two team names"
        echo "Usage: $0 head2head \"Team1\" \"Team2\" [limit]"
        return 1
    fi
    
    log_info "Showing last $limit matches between: $team1 vs $team2"
    
    echo
    echo "=== HEAD TO HEAD: $team1 vs $team2 (Last $limit Matches) ==="
    
    # Get team IDs for more accurate matching
    local team1_id=$(sqlite3 "$DB_FILE" "SELECT id FROM teams WHERE name LIKE '%$team1%' LIMIT 1;")
    local team2_id=$(sqlite3 "$DB_FILE" "SELECT id FROM teams WHERE name LIKE '%$team2%' LIMIT 1;")
    
    if [ -z "$team1_id" ] || [ -z "$team2_id" ]; then
        log_error "Could not find one or both teams. Check team names and try again."
        return 1
    fi
    
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        s.id as season,
        m.matchday,
        ht.name as home_team,
        m.home_score || ' - ' || m.away_score as score,
        at.name as away_team,
        CASE 
            WHEN m.home_score > m.away_score THEN ht.name || ' WIN'
            WHEN m.home_score < m.away_score THEN at.name || ' WIN'
            ELSE 'DRAW'
        END as result,
        CASE 
            WHEN (m.home_score > m.away_score AND ht.id = $team1_id) OR 
                 (m.away_score > m.home_score AND at.id = $team1_id) THEN '$team1'
            WHEN (m.home_score > m.away_score AND ht.id = $team2_id) OR 
                 (m.away_score > m.home_score AND at.id = $team2_id) THEN '$team2'
            ELSE 'DRAW'
        END as winner,
        r.name as referee,
        m.venue as stadium
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    JOIN seasons s ON m.season_id = s.id
    LEFT JOIN referees r ON m.referee_id = r.id
    WHERE ((ht.id = $team1_id AND at.id = $team2_id) OR 
           (ht.id = $team2_id AND at.id = $team1_id))
      AND m.status = 'FINISHED'
    ORDER BY m.match_date DESC
    LIMIT $limit;
    "
    
    # Show head-to-head statistics
    echo
    echo "=== HEAD-TO-HEAD STATISTICS ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        COUNT(*) as total_matches,
        SUM(CASE 
            WHEN (m.home_score > m.away_score AND ht.id = $team1_id) OR 
                 (m.away_score > m.home_score AND at.id = $team1_id) THEN 1 
            ELSE 0 
        END) as \"$team1_wins\",
        SUM(CASE 
            WHEN (m.home_score > m.away_score AND ht.id = $team2_id) OR 
                 (m.away_score > m.home_score AND at.id = $team2_id) THEN 1 
            ELSE 0 
        END) as \"$team2_wins\",
        SUM(CASE 
            WHEN m.home_score = m.away_score THEN 1 
            ELSE 0 
        END) as draws,
        SUM(CASE 
            WHEN ht.id = $team1_id THEN m.home_score 
            ELSE m.away_score 
        END) as \"$team1_goals\",
        SUM(CASE 
            WHEN ht.id = $team2_id THEN m.home_score 
            ELSE m.away_score 
        END) as \"$team2_goals\",
        ROUND(
            SUM(CASE 
                WHEN (m.home_score > m.away_score AND ht.id = $team1_id) OR 
                     (m.away_score > m.home_score AND at.id = $team1_id) THEN 1 
                ELSE 0 
            END) * 100.0 / COUNT(*), 1
        ) as \"$team1_win_pct%\",
        ROUND(
            SUM(CASE 
                WHEN (m.home_score > m.away_score AND ht.id = $team2_id) OR 
                     (m.away_score > m.home_score AND at.id = $team2_id) THEN 1 
                ELSE 0 
            END) * 100.0 / COUNT(*), 1
        ) as \"$team2_win_pct%\"
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE ((ht.id = $team1_id AND at.id = $team2_id) OR 
           (ht.id = $team2_id AND at.id = $team1_id))
      AND m.status = 'FINISHED';
    "
    
    # Show recent trends
    echo
    echo "=== RECENT TRENDS (Last 5 Matches) ==="
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        CASE 
            WHEN (m.home_score > m.away_score AND ht.id = $team1_id) OR 
                 (m.away_score > m.home_score AND at.id = $team1_id) THEN '$team1'
            WHEN (m.home_score > m.away_score AND ht.id = $team2_id) OR 
                 (m.away_score > m.home_score AND at.id = $team2_id) THEN '$team2'
            ELSE 'DRAW'
        END as result,
        COUNT(*) as count
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE ((ht.id = $team1_id AND at.id = $team2_id) OR 
           (ht.id = $team2_id AND at.id = $team1_id))
      AND m.status = 'FINISHED'
    GROUP BY result
    ORDER BY count DESC;
    "
}

show_head_to_head_detailed() {
    local team1="$1"
    local team2="$2"
    
    if [ -z "$team1" ] || [ -z "$team2" ]; then
        log_error "Please provide two team names"
        return 1
    fi
    
    log_info "Showing detailed head-to-head analysis: $team1 vs $team2"
    
    # Get team IDs
    local team1_id=$(sqlite3 "$DB_FILE" "SELECT id FROM teams WHERE name LIKE '%$team1%' LIMIT 1;")
    local team2_id=$(sqlite3 "$DB_FILE" "SELECT id FROM teams WHERE name LIKE '%$team2%' LIMIT 1;")
    
    echo
    echo "=== DETAILED HEAD-TO-HEAD ANALYSIS: $team1 vs $team2 ==="
    
    # Home vs Away performance
    echo
    echo "🏠 HOME PERFORMANCE:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        'When ' || t1.name || ' plays at home' as scenario,
        COUNT(*) as matches,
        SUM(CASE WHEN m.home_score > m.away_score THEN 1 ELSE 0 END) as home_wins,
        SUM(CASE WHEN m.home_score < m.away_score THEN 1 ELSE 0 END) as away_wins,
        SUM(CASE WHEN m.home_score = m.away_score THEN 1 ELSE 0 END) as draws,
        AVG(m.home_score) as avg_home_goals,
        AVG(m.away_score) as avg_away_goals
    FROM matches m
    JOIN teams t1 ON m.home_team_id = t1.id
    JOIN teams t2 ON m.away_team_id = t2.id
    WHERE t1.id = $team1_id AND t2.id = $team2_id
      AND m.status = 'FINISHED';
    "
    
    echo
    echo "✈️ AWAY PERFORMANCE:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        'When ' || t1.name || ' plays away' as scenario,
        COUNT(*) as matches,
        SUM(CASE WHEN m.home_score < m.away_score THEN 1 ELSE 0 END) as away_wins,
        SUM(CASE WHEN m.home_score > m.away_score THEN 1 ELSE 0 END) as home_wins,
        SUM(CASE WHEN m.home_score = m.away_score THEN 1 ELSE 0 END) as draws,
        AVG(m.away_score) as avg_away_goals,
        AVG(m.home_score) as avg_home_goals
    FROM matches m
    JOIN teams t1 ON m.away_team_id = t1.id
    JOIN teams t2 ON m.home_team_id = t2.id
    WHERE t1.id = $team1_id AND t2.id = $team2_id
      AND m.status = 'FINISHED';
    "
    
    # Biggest wins
    echo
    echo "🏆 BIGGEST WINS:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        ht.name || ' ' || m.home_score || ' - ' || m.away_score || ' ' || at.name as scoreline,
        CASE 
            WHEN m.home_score > m.away_score THEN ht.name || ' win by ' || (m.home_score - m.away_score)
            WHEN m.away_score > m.home_score THEN at.name || ' win by ' || (m.away_score - m.home_score)
        END as margin
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE ((ht.id = $team1_id AND at.id = $team2_id) OR 
           (ht.id = $team2_id AND at.id = $team1_id))
      AND m.status = 'FINISHED'
    ORDER BY ABS(m.home_score - m.away_score) DESC, m.match_date DESC
    LIMIT 3;
    "
    
    # Highest scoring games
    echo
    echo "⚽ HIGHEST SCORING GAMES:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as date,
        ht.name || ' ' || m.home_score || ' - ' || m.away_score || ' ' || at.name as scoreline,
        (m.home_score + m.away_score) as total_goals
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE ((ht.id = $team1_id AND at.id = $team2_id) OR 
           (ht.id = $team2_id AND at.id = $team1_id))
      AND m.status = 'FINISHED'
    ORDER BY total_goals DESC, m.match_date DESC
    LIMIT 3;
    "
}

show_next_matchday_predictions() {
    local matchday="${1:-next}"
    
    log_info "Generating predictions for $matchday matchday"
    
    echo
    echo "🎯 PREDICTIONS FOR $matchday MATCHDAY"
    echo "==========================================="
    
    # Create a temporary file to store matches
    local temp_file=$(mktemp)
    
    # Get upcoming matches and store in temp file
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.id as match_id,
        m.match_date,
        ht.name as home_team,
        at.name as away_team,
        m.status
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT 10;
    " > "$temp_file"
    
    # Skip header and process each match
    tail -n +2 "$temp_file" | while IFS='|' read -r match_id match_date home_team away_team status; do
        # Remove extra whitespace
        home_team=$(echo "$home_team" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        away_team=$(echo "$away_team" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        match_date=$(echo "$match_date" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -n "$home_team" ] && [ -n "$away_team" ] && [ "$home_team" != "home_team" ]; then
            echo
            echo "===================================================================="
            echo "🆚 $home_team vs $away_team"
            echo "📅 $match_date"
            echo "===================================================================="
            
            # Call prediction function
            show_match_prediction "$home_team" "$away_team" 2>/dev/null | grep -A 20 "🎲 PREDICTION CALCULATION" || \
            echo "   Not enough historical data for accurate prediction"
            
            echo
        fi
    done
    
    # Clean up
    rm -f "$temp_file"
}

# Alternative simpler version for debugging
show_next_matchday_predictions_simple() {
    local matchday="${1:-next}"
    
    log_info "Generating predictions for $matchday matchday"
    
    echo
    echo "🎯 PREDICTIONS FOR $matchday MATCHDAY"
    echo "==========================================="
    
    # Get upcoming matches using line-by-line processing
    sqlite3 "$DB_FILE" "
    SELECT 
        ht.name || '|' || at.name || '|' || m.match_date
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT 10;
    " | while IFS='|' read -r home_team away_team match_date; do
        if [ -n "$home_team" ] && [ -n "$away_team" ]; then
            echo
            echo "===================================================================="
            echo "🆚 $home_team vs $away_team"
            echo "📅 $match_date"
            echo "===================================================================="
            
            # Call prediction function
            show_match_prediction "$home_team" "$away_team" 2>/dev/null | tail -15
            echo
        fi
    done
}

# Even simpler version with better error handling
show_next_matchday_predictions_fixed() {
    local matchday="${1:-next}"
    
    log_info "Generating predictions for $matchday matchday"
    
    echo
    echo "🎯 PREDICTIONS FOR $matchday MATCHDAY"
    echo "==========================================="
    
    # Use -list mode for cleaner output
    sqlite3 -list "$DB_FILE" "
    SELECT 
        ht.name, 
        at.name, 
        m.match_date
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.status IN ('SCHEDULED', 'TIMED')
      AND m.match_date >= date('now')
    ORDER BY m.match_date ASC
    LIMIT 10;
    " | while IFS='|' read -r home_team away_team match_date; do
        if [ -n "$home_team" ] && [ -n "$away_team" ] && [ "$home_team" != "home_team" ]; then
            echo
            echo "===================================================================="
            echo "🆚 $home_team vs $away_team"
            echo "📅 $match_date"
            echo "===================================================================="
            
            # Show quick prediction summary
            show_prediction_summary "$home_team" "$away_team"
            echo
        fi
    done
}

# Quick prediction summary (faster than full prediction)
show_prediction_summary() {
    local home_team="$1"
    local away_team="$2"
    
    local home_id=$(sqlite3 "$DB_FILE" "SELECT id FROM teams WHERE name LIKE '%$home_team%' LIMIT 1;")
    local away_id=$(sqlite3 "$DB_FILE" "SELECT id FROM teams WHERE name LIKE '%$away_team%' LIMIT 1;")
    
    if [ -z "$home_id" ] || [ -z "$away_id" ]; then
        echo "   ❌ Cannot find team data"
        return 1
    fi
    
    # Quick prediction calculation
    local prediction=$(sqlite3 "$DB_FILE" "
    WITH h2h AS (
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN (m.home_score > m.away_score AND ht.id = $home_id) THEN 1 ELSE 0 END) as home_wins,
            SUM(CASE WHEN (m.away_score > m.home_score AND at.id = $away_id) THEN 1 ELSE 0 END) as away_wins,
            SUM(CASE WHEN m.home_score = m.away_score THEN 1 ELSE 0 END) as draws
        FROM matches m
        JOIN teams ht ON m.home_team_id = ht.id
        JOIN teams at ON m.away_team_id = at.id
        WHERE ((ht.id = $home_id AND at.id = $away_id) OR (ht.id = $away_id AND at.id = $home_id))
          AND m.status = 'FINISHED'
    ),
    home_form AS (
        SELECT AVG(CASE WHEN m.home_score > m.away_score THEN 1.0 ELSE 0.0 END) as win_rate
        FROM matches m
        WHERE m.home_team_id = $home_id AND m.status = 'FINISHED'
        ORDER BY m.match_date DESC LIMIT 5
    ),
    away_form AS (
        SELECT AVG(CASE WHEN m.away_score > m.home_score THEN 1.0 ELSE 0.0 END) as win_rate
        FROM matches m
        WHERE m.away_team_id = $away_id AND m.status = 'FINISHED'
        ORDER BY m.match_date DESC LIMIT 5
    )
    SELECT 
        CASE 
            WHEN h2h.total > 0 THEN 
                ROUND((h2h.home_wins * 0.4 / h2h.total + home_form.win_rate * 0.4 + 0.2) * 100, 1)
            ELSE ROUND((home_form.win_rate * 0.6 + 0.4) * 100, 1)
        END as home_win_chance,
        CASE 
            WHEN h2h.total > 0 THEN 
                ROUND((h2h.away_wins * 0.4 / h2h.total + away_form.win_rate * 0.4) * 100, 1)
            ELSE ROUND((away_form.win_rate * 0.6) * 100, 1)
        END as away_win_chance,
        CASE 
            WHEN h2h.total > 0 THEN 
                ROUND((h2h.draws * 0.4 / h2h.total + (1 - home_form.win_rate - away_form.win_rate) * 0.6) * 100, 1)
            ELSE ROUND(20.0, 1)
        END as draw_chance,
        h2h.total as h2h_matches
    FROM h2h, home_form, away_form;
    ")
    
    echo "$prediction" | awk -F'|' '
    {
        printf "   🏆 Win Probabilities:\n"
        printf "      %s: %.1f%%\n", "'"$home_team"'", $1
        printf "      %s: %.1f%%\n", "'"$away_team"'", $2  
        printf "      Draw: %.1f%%\n", $3
        printf "   📊 Based on %d historical matches\n", $4
    }'
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-stats}" in
        "stats")
            show_stats
            ;;
        "team")
            show_team_matches "$2"
            ;;
        "season")
            show_season_matches "$2"
            ;;
        "next")
            show_next_game "$2"
            ;;
        "fixtures")
            show_upcoming_fixtures "$2" "$3"
            ;;
        "form")
            show_team_form "$2" "$3"
            ;;
        "analytics")
            show_team_analytics "$2"
            ;;
        "head2head")
            show_head_to_head "$2" "$3" "$4"
            ;;
        "h2h")
            show_head_to_head_detailed "$2" "$3"
            ;;
        "predict")
            show_match_prediction "$2" "$3"
            ;;
        "predictions")
            show_next_matchday_predictions_fixed "$2"
            ;;
        "tables")
            sqlite3 "$DB_FILE" ".tables"
            ;;
        "schema")
            sqlite3 "$DB_FILE" ".schema"
            ;;
        *)
            echo "Usage: $0 {stats|team <name>|season <year>|next <team>|fixtures <team> [limit]|form <team> [limit]|analytics <team>|head2head <team1> <team2> [limit]|h2h <team1> <team2>|predict <home_team> <away_team>|predictions [matchday]|tables|schema}"
            ;;
    esac
fi
