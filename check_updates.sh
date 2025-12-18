#!/bin/bash
# Diagnostic script to check if updates are working
source config.sh

echo "🔍 CHECKING DATA UPDATE STATUS"
echo "════════════════════════════════════════════════════════════════════════════════"

# Check last update times
echo "📅 LAST UPDATED MATCHES:"
sqlite3 -header -column "$DB_FILE" "
SELECT 
    strftime('%Y-%m-%d %H:%M', m.last_updated) as 'Last Updated',
    m.match_date as 'Match Date',
    ht.name as 'Home',
    m.home_score || ' - ' || m.away_score as 'Score',
    at.name as 'Away',
    m.status
FROM matches m
JOIN teams ht ON m.home_team_id = ht.id
JOIN teams at ON m.away_team_id = at.id
ORDER BY m.last_updated DESC
LIMIT 5;
"

echo
echo "📊 TODAY'S UPDATES:"
sqlite3 -header -column "$DB_FILE" "
SELECT 
    COUNT(*) as 'Matches Updated Today',
    SUM(CASE WHEN m.status = 'FINISHED' THEN 1 ELSE 0 END) as 'Finished',
    SUM(CASE WHEN m.status IN ('SCHEDULED', 'TIMED') THEN 1 ELSE 0 END) as 'Upcoming',
    SUM(CASE WHEN m.status = 'IN_PLAY' THEN 1 ELSE 0 END) as 'Live'
FROM matches m
WHERE date(m.last_updated) = date('now');
"

echo
echo "⚽ RECENT MATCHES (Last 3 Days):"
sqlite3 -header -column "$DB_FILE" "
SELECT 
    m.match_date as 'Date',
    ht.name as 'Home',
    m.home_score || ' - ' || m.away_score as 'Score',
    at.name as 'Away',
    m.status,
    CASE 
        WHEN m.status = 'FINISHED' AND date(m.match_date) = date('now', '-1 day') THEN '✅ Yesterday'
        WHEN m.status = 'FINISHED' AND date(m.match_date) = date('now') THEN '✅ Today'
        WHEN m.status = 'FINISHED' THEN '✅ Recent'
        ELSE '⏳ ' || m.status
    END as 'Status'
FROM matches m
JOIN teams ht ON m.home_team_id = ht.id
JOIN teams at ON m.away_team_id = at.id
WHERE m.match_date >= date('now', '-3 days')
ORDER BY m.match_date DESC, m.last_updated DESC
LIMIT 10;
"

echo
echo "❓ MATCHES WITH MISSING DATA:"
sqlite3 -header -column "$DB_FILE" "
SELECT 
    m.match_date as 'Date',
    ht.name as 'Home',
    m.home_score || ' - ' || m.away_score as 'Score',
    at.name as 'Away',
    m.status,
    CASE 
        WHEN m.status = 'FINISHED' AND (m.home_score IS NULL OR m.away_score IS NULL) THEN '❌ Missing Scores'
        WHEN m.status = 'FINISHED' AND m.home_score = 0 AND m.away_score = 0 THEN '⚠️ 0-0 Score'
        ELSE '✅ OK'
    END as 'Check'
FROM matches m
JOIN teams ht ON m.home_team_id = ht.id
JOIN teams at ON m.away_team_id = at.id
WHERE m.match_date >= date('now', '-7 days')
  AND (m.status = 'FINISHED' AND (m.home_score IS NULL OR m.away_score IS NULL OR (m.home_score = 0 AND m.away_score = 0)))
ORDER BY m.match_date DESC
LIMIT 5;
"

echo
echo "💡 RECOMMENDED ACTIONS:"
echo "1. Run: make force-update DAYS=3    # Force update last 3 days"
echo "2. Run: make fix-scores             # Fix missing scores"
echo "3. Run: make daily                  # Normal daily update"
