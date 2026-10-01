#!/bin/bash
# table_column.sh - Better formatted table with colors

DB_FILE="$HOME/Desktop/epl/epl_data.db"

# First, update the data
echo -e "${BLUE}[INFO] Updating match data...${RESET}"
"$HOME/Desktop/epl/update.sh"

# Color definitions
WHITE='\033[1;97m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${GREEN}[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - All dependencies available${RESET}"
echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Generating EPL table for season: 2025${RESET}"
echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "                           PREMIER LEAGUE TABLE 2025/2026"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Print header (without Icon)
printf "%-3s %-24s %-3s %-3s %-3s %-3s %-4s %-4s %-5s %-5s %-8s\n" \
    "pos" "Team" "P" "W" "D" "L" "GF" "GA" "GD" "Pts" "Euro"
printf "%-3s %-24s %-3s %-3s %-3s %-3s %-4s %-4s %-5s %-5s %-8s\n" \
    "---" "--------------------------" "--" "--" "--" "--" "---" "---" "----" "----" "--------"

# Get the data
sqlite3 "$DB_FILE" "
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
),
ranked_teams AS (
    SELECT
        ms.*,
        t.name,
        ROW_NUMBER() OVER (ORDER BY (ms.W * 3 + ms.D) DESC, (ms.GF - ms.GA) DESC, ms.GF DESC) as pos
    FROM match_stats ms
    JOIN teams t ON ms.team_id = t.id
    WHERE ms.P > 0
)
SELECT
    pos,
    name,
    P,
    W,
    D,
    L,
    GF,
    GA,
    (GF - GA) as GD,
    (W * 3 + D) as Pts,
    CASE
        WHEN pos <= 4 THEN 'UCL'
        WHEN pos = 5 THEN 'UEL'
        WHEN pos = 6 THEN 'UECL'
        WHEN pos >= 18 THEN 'REL'
        ELSE '---'
    END as Euro
FROM ranked_teams
ORDER BY pos;" | \
while IFS='|' read -r pos name P W D L GF GA GD Pts Euro; do
    # Skip if no data
    [[ -z "$pos" ]] && continue
    
    # Truncate team name if needed
    if [[ ${#name} -gt 24 ]]; then
        name="${name:0:22}.."
    fi
    
    # Determine color based on Euro column
    color=""
    if [[ "$Euro" == "UCL" ]]; then
        color="$CYAN"
    elif [[ "$Euro" == "UEL" ]]; then
        color="$GREEN"
    elif [[ "$Euro" == "UECL" ]]; then
        color="$PURPLE"
    elif [[ "$Euro" == "REL" ]]; then
        color="$RED"
    else
        color="$WHITE"
    fi
    
    # Format and print the line with color (without Icon)
    printf "${color}%-3s %-24s %-3s %-3s %-3s %-3s %-4s %-4s %-5s %-5s %-8s${RESET}\n" \
        "$pos" "$name" "$P" "$W" "$D" "$L" "$GF" "$GA" "$GD" "$Pts" "$Euro"
done

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"

# Colorized legend (without Icon reference)
echo -e "Legend: ${CYAN}UCL${RESET}=Champions League, ${GREEN}UEL${RESET}=Europa League, ${PURPLE}UECL${RESET}=Conference League, ${RED}REL${RESET}=Relegation, ${WHITE}MID${RESET}=Mid-table"
echo -e "${CYAN}— Premier League Table 2025/26${RESET}"
echo "════════════════════════════════════════════════════════════════════════════════"
