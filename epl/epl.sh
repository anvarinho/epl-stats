#!/bin/bash

# EPL Table - Simple version
DB_FILE="epl.db"

show_help() {
    echo "Usage: $0 {table|detailed|goals|form|summary} [season]"
    echo ""
    echo "Commands:"
    echo "  table     - Show league table"
    echo "  detailed  - Show table with home/away stats"
    echo "  goals     - Show goal statistics"
    echo "  form      - Show recent form"
    echo "  summary   - Show season summary"
    echo ""
    echo "Example: $0 table 2023"
}

show_table() {
    local season="${1:-2023}"
    
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    PREMIER LEAGUE $season/$((season+1))                    ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    
    sqlite3 -header -column "$DB_FILE" "
    WITH team_stats AS (
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
            SUM(CASE WHEN m.home_team_id = t.id THEN m.away_score ELSE m.home_score END) as GA
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season AND m.status = 'FINISHED'
        GROUP BY t.id
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY (W*3+D) DESC, (GF-GA) DESC, GF DESC) as Pos,
        team as Team,
        P,
        W,
        D,
        L,
        GF,
        GA,
        (GF-GA) as GD,
        (W*3+D) as Pts
    FROM team_stats
    ORDER BY Pts DESC, GD DESC, GF DESC;
    "
}

show_detailed_table() {
    local season="${1:-2023}"
    
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                  DETAILED TABLE $season/$((season+1))                           ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    
    sqlite3 -header -column "$DB_FILE" "
    SELECT
        ROW_NUMBER() OVER (ORDER BY (W*3+D) DESC, GD DESC, GF DESC) as Pos,
        team as Team,
        P,
        W,
        D,
        L,
        GF,
        GA,
        GD,
        Pts,
        home_record as Home,
        away_record as Away
    FROM (
        SELECT
            t.name as team,
            COUNT(*) as P,
            SUM(CASE WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 1 ELSE 0 END) as W,
            SUM(CASE WHEN m.home_score = m.away_score THEN 1 ELSE 0 END) as D,
            SUM(CASE WHEN (m.home_team_id = t.id AND m.home_score < m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score < m.home_score) THEN 1 ELSE 0 END) as L,
            SUM(CASE WHEN m.home_team_id = t.id THEN m.home_score ELSE m.away_score END) as GF,
            SUM(CASE WHEN m.home_team_id = t.id THEN m.away_score ELSE m.home_score END) as GA,
            (SUM(CASE WHEN m.home_team_id = t.id THEN m.home_score ELSE m.away_score END) - 
             SUM(CASE WHEN m.home_team_id = t.id THEN m.away_score ELSE m.home_score END)) as GD,
            (SUM(CASE WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 3
                    WHEN m.home_score = m.away_score THEN 1 ELSE 0 END)) as Pts,
            (SELECT group_concat(W||'-'||D||'-'||L) FROM (
                SELECT
                    SUM(CASE WHEN home_score > away_score THEN 1 ELSE 0 END) as W,
                    SUM(CASE WHEN home_score = away_score THEN 1 ELSE 0 END) as D,
                    SUM(CASE WHEN home_score < away_score THEN 1 ELSE 0 END) as L
                FROM matches
                WHERE home_team_id = t.id AND season_id = $season AND status = 'FINISHED'
            )) as home_record,
            (SELECT group_concat(W||'-'||D||'-'||L) FROM (
                SELECT
                    SUM(CASE WHEN away_score > home_score THEN 1 ELSE 0 END) as W,
                    SUM(CASE WHEN away_score = home_score THEN 1 ELSE 0 END) as D,
                    SUM(CASE WHEN away_score < home_score THEN 1 ELSE 0 END) as L
                FROM matches
                WHERE away_team_id = t.id AND season_id = $season AND status = 'FINISHED'
            )) as away_record
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season AND m.status = 'FINISHED'
        GROUP BY t.id
    )
    ORDER BY Pts DESC, GD DESC, GF DESC;
    "
}

show_goals() {
    local season="${1:-2023}"
    
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                       GOAL STATS $season/$((season+1))                       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    
    echo ""
    echo "TOP SCORING TEAMS:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT
        ROW_NUMBER() OVER (ORDER BY goals DESC) as '#',
        team as Team,
        goals as Goals,
        ROUND(goals*1.0/games, 2) as 'Avg'
    FROM (
        SELECT
            t.name as team,
            COUNT(*) as games,
            SUM(CASE WHEN m.home_team_id = t.id THEN m.home_score ELSE m.away_score END) as goals
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season AND m.status = 'FINISHED'
        GROUP BY t.id
    )
    ORDER BY goals DESC
    LIMIT 10;
    "
    
    echo ""
    echo "HIGHEST SCORING MATCHES:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT
        date as Date,
        home as Home,
        score as Score,
        away as Away,
        total as 'Total Goals'
    FROM (
        SELECT
            m.match_date as date,
            ht.name as home,
            m.home_score || '-' || m.away_score as score,
            at.name as away,
            (m.home_score + m.away_score) as total
        FROM matches m
        JOIN teams ht ON m.home_team_id = ht.id
        JOIN teams at ON m.away_team_id = at.id
        WHERE m.season_id = $season AND m.status = 'FINISHED'
    )
    ORDER BY total DESC
    LIMIT 5;
    "
}

show_form() {
    local season="${1:-2023}"
    local matches="${2:-5}"
    
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                       FORM GUIDE $season/$((season+1))                       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    
    sqlite3 -header -column "$DB_FILE" "
    SELECT
        team as Team,
        form as 'Last $matches',
        Pts as 'Pts',
        W as W,
        D as D,
        L as L
    FROM (
        SELECT
            t.name as team,
            GROUP_CONCAT(
                CASE
                    WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR
                         (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 'W'
                    WHEN m.home_score = m.away_score THEN 'D'
                    ELSE 'L'
                END,
                ' ' ORDER BY m.match_date DESC
            ) as form,
            SUM(CASE
                WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR
                     (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 3
                WHEN m.home_score = m.away_score THEN 1
                ELSE 0
            END) as Pts,
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
            END) as L
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season AND m.status = 'FINISHED'
        GROUP BY t.id
        HAVING COUNT(*) >= $matches
    )
    ORDER BY Pts DESC
    LIMIT 20;
    "
}

show_summary() {
    local season="${1:-2023}"
    
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                     SEASON SUMMARY $season/$((season+1))                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    
    sqlite3 -header -column "$DB_FILE" "
    SELECT
        'Matches' as Statistic,
        COUNT(*) as Value
    FROM matches
    WHERE season_id = $season AND status = 'FINISHED'
    
    UNION ALL
    
    SELECT
        'Total Goals',
        SUM(home_score + away_score)
    FROM matches
    WHERE season_id = $season AND status = 'FINISHED'
    
    UNION ALL
    
    SELECT
        'Avg Goals/Match',
        ROUND(AVG(home_score + away_score), 2)
    FROM matches
    WHERE season_id = $season AND status = 'FINISHED'
    
    UNION ALL
    
    SELECT
        'Home Wins',
        COUNT(*) || ' (' || ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM matches WHERE season_id=$season AND status='FINISHED'),1) || '%)'
    FROM matches
    WHERE season_id = $season AND status = 'FINISHED' AND home_score > away_score
    
    UNION ALL
    
    SELECT
        'Draws',
        COUNT(*) || ' (' || ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM matches WHERE season_id=$season AND status='FINISHED'),1) || '%)'
    FROM matches
    WHERE season_id = $season AND status = 'FINISHED' AND home_score = away_score;
    "
}

# Main
if [ $# -eq 0 ]; then
    show_table 2023
    exit 0
fi

case "$1" in
    table)
        show_table "${2:-2023}"
        ;;
    detailed)
        show_detailed_table "${2:-2023}"
        ;;
    goals)
        show_goals "${2:-2023}"
        ;;
    form)
        show_form "${2:-2023}" "${3:-5}"
        ;;
    summary)
        show_summary "${2:-2023}"
        ;;
    help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use: $0 help"
        ;;
esac
