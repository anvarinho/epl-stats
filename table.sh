#!/bin/bash
# table_column.sh - Better formatted table

DB_FILE="epl_data.db"

echo -e "\033[0;32m[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - All dependencies available\033[0m"
echo -e "\033[0;34m[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Generating EPL table for season: 2025\033[0m"
echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "                           PREMIER LEAGUE TABLE 2025/2026"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Generate table with column formatting
sqlite3 -header -column -cmd ".width 3 26 2 2 2 2 3 3 4 4 12" "$DB_FILE" "
WITH match_stats AS (
    SELECT 
        team_id,
        SUM(played) as P,
        SUM(wins) as W,
        SUM(draws) as D,
        SUM(losses) as L,
        SUM(gf) as GF,
        SUM(ga) as GA
    FROM (
        SELECT 
            home_team_id as team_id,
            1 as played,
            CASE WHEN home_score > away_score THEN 1 ELSE 0 END as wins,
            CASE WHEN home_score = away_score THEN 1 ELSE 0 END as draws,
            CASE WHEN home_score < away_score THEN 1 ELSE 0 END as losses,
            home_score as gf,
            away_score as ga
        FROM matches
        WHERE match_date >= '2025-08-15' AND status = 'FINISHED'
        
        UNION ALL
        
        SELECT 
            away_team_id as team_id,
            1 as played,
            CASE WHEN away_score > home_score THEN 1 ELSE 0 END as wins,
            CASE WHEN away_score = home_score THEN 1 ELSE 0 END as draws,
            CASE WHEN away_score < home_score THEN 1 ELSE 0 END as losses,
            away_score as gf,
            home_score as ga
        FROM matches
        WHERE match_date >= '2025-08-15' AND status = 'FINISHED'
    )
    GROUP BY team_id
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY (W * 3 + D) DESC, (GF - GA) DESC, GF DESC) as pos,
    CASE 
        WHEN LENGTH(t.name) > 24 THEN SUBSTR(t.name, 1, 22) || '..'
        ELSE t.name
    END as Team,
    P,
    W,
    D,
    L,
    GF,
    GA,
    (GF - GA) as GD,
    (W * 3 + D) as Pts,
    CASE 
        WHEN ROW_NUMBER() OVER (ORDER BY (W * 3 + D) DESC, (GF - GA) DESC, GF DESC) <= 4 THEN 'UCL ✅'
        WHEN ROW_NUMBER() OVER (ORDER BY (W * 3 + D) DESC, (GF - GA) DESC, GF DESC) = 5 THEN 'UEL ✅'
        WHEN ROW_NUMBER() OVER (ORDER BY (W * 3 + D) DESC, (GF - GA) DESC, GF DESC) = 6 THEN 'UECL ⚽'
        WHEN ROW_NUMBER() OVER (ORDER BY (W * 3 + D) DESC, (GF - GA) DESC, GF DESC) >= 18 THEN 'REL ❌'
        ELSE '----'
    END as 'European/Rel'
FROM match_stats ms
JOIN teams t ON ms.team_id = t.id
WHERE P > 0
ORDER BY (W * 3 + D) DESC, (GF - GA) DESC, GF DESC;"

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Legend: UCL=Champions League, UEL=Europa League, UECL=Conference League, REL=Relegation"
echo "════════════════════════════════════════════════════════════════════════════════"
