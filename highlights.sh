#!/bin/bash
# tour_highlights_simple.sh - Clean highlights from last matchday

DB_FILE="epl_data.db"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "                    PREMIER LEAGUE - LAST TOUR HIGHLIGHTS"
echo "════════════════════════════════════════════════════════════════════════════════"

# Get latest matchday
LATEST=$(sqlite3 "$DB_FILE" "
SELECT MAX(matchday) 
FROM matches 
WHERE status = 'FINISHED' 
  AND match_date >= '2025-08-15';")

echo ""
echo "📅 MATCHDAY $LATEST RESULTS"
echo "────────────────────────────────────────────────────────────────────────────────"

# Show all results
sqlite3 "$DB_FILE" << 'EOF'
.headers off
.mode line

WITH last_tour AS (
    SELECT m.*, h.name as home_name, h.tla_code as home_tla,
           a.name as away_name, a.tla_code as away_tla
    FROM matches m
    JOIN teams h ON m.home_team_id = h.id
    JOIN teams a ON m.away_team_id = a.id
    WHERE m.matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
      AND m.status = 'FINISHED'
    ORDER BY m.match_date, m.id
)
SELECT 
    '🏟️  ' || home_tla || ' vs ' || away_tla || 
    '  ' || home_score || '-' || away_score || 
    CASE 
        WHEN home_score > away_score THEN '  (' || home_tla || ' wins)'
        WHEN away_score > home_score THEN '  (' || away_tla || ' wins)'
        ELSE '  (Draw)'
    END as Result
FROM last_tour;
EOF

echo ""
echo "📊 TOUR STATS"
echo "────────────────────────────────────────────────────────────────────────────────"

# Get statistics
sqlite3 "$DB_FILE" << 'EOF'
.headers off

SELECT 'Total Matches:        ' || COUNT(*) 
FROM matches 
WHERE matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND status = 'FINISHED';

SELECT 'Total Goals:          ' || SUM(home_score + away_score)
FROM matches 
WHERE matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND status = 'FINISHED';

SELECT 'Average Goals/Match:  ' || ROUND(AVG(home_score + away_score), 2)
FROM matches 
WHERE matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND status = 'FINISHED';

SELECT 'Home Wins:            ' || SUM(CASE WHEN home_score > away_score THEN 1 ELSE 0 END)
FROM matches 
WHERE matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND status = 'FINISHED';

SELECT 'Away Wins:            ' || SUM(CASE WHEN away_score > home_score THEN 1 ELSE 0 END)
FROM matches 
WHERE matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND status = 'FINISHED';

SELECT 'Draws:                ' || SUM(CASE WHEN home_score = away_score THEN 1 ELSE 0 END)
FROM matches 
WHERE matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND status = 'FINISHED';
EOF

echo ""
echo "⭐ STANDOUT PERFORMANCES"
echo "────────────────────────────────────────────────────────────────────────────────"

# Get standout performances
sqlite3 "$DB_FILE" << 'EOF'
.headers off

-- Biggest win
SELECT 'Biggest Win:          ' || 
       h.tla_code || ' ' || m.home_score || '-' || m.away_score || ' ' || a.tla_code || 
       ' (' || ABS(m.home_score - m.away_score) || ' goals)'
FROM matches m
JOIN teams h ON m.home_team_id = h.id
JOIN teams a ON m.away_team_id = a.id
WHERE m.matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND m.status = 'FINISHED'
ORDER BY ABS(m.home_score - m.away_score) DESC
LIMIT 1;

-- Highest scoring
SELECT 'Highest Scoring:      ' || 
       h.tla_code || ' ' || m.home_score || '-' || m.away_score || ' ' || a.tla_code || 
       ' (' || (m.home_score + m.away_score) || ' goals)'
FROM matches m
JOIN teams h ON m.home_team_id = h.id
JOIN teams a ON m.away_team_id = a.id
WHERE m.matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND m.status = 'FINISHED'
ORDER BY (m.home_score + m.away_score) DESC
LIMIT 1;

-- Clean sheets
SELECT 'Clean Sheets:         ' || 
       GROUP_CONCAT(
           CASE 
               WHEN m.home_score = 0 THEN a.tla_code
               WHEN m.away_score = 0 THEN h.tla_code
           END, ', '
       )
FROM matches m
JOIN teams h ON m.home_team_id = h.id
JOIN teams a ON m.away_team_id = a.id
WHERE m.matchday = (SELECT MAX(matchday) FROM matches WHERE status = 'FINISHED' AND match_date >= '2025-08-15')
  AND m.status = 'FINISHED'
  AND (m.home_score = 0 OR m.away_score = 0);
EOF

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Data through: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════════════════════"
