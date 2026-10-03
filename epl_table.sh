#!/bin/bash

# EPL Table Generator - Shows complete league table for a specific season
source config.sh

show_season_table() {
    local season="${1:-2023}"
    
    log_info "Generating EPL table for season: $season"
    
    # First, verify we have data for this season
    local match_count=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) 
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED';
    ")
    
    if [ "$match_count" -eq 0 ]; then
        log_error "No finished matches found for season $season"
        return 1
    fi
    
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                           PREMIER LEAGUE TABLE $season/$((season + 1))"
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    # Generate league table using standard Premier League rules:
    # 1. Points (3 for win, 1 for draw, 0 for loss)
    # 2. Goal Difference
    # 3. Goals Scored
    # 4. Head-to-Head (not implemented here)
    # 5. Fewest Red/Yellow Cards (not tracked)
    
    local table_output
    table_output=$(sqlite3 -header -column "$DB_FILE" "
    WITH team_stats AS (
        SELECT 
            t.id as team_id,
            t.name as team_name,
            t.tla_code as team_code,
            -- Count matches
            COUNT(*) as played,
            -- Calculate wins
            SUM(CASE 
                WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR 
                     (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 1 
                ELSE 0 
            END) as wins,
            -- Calculate draws  
            SUM(CASE 
                WHEN m.home_score = m.away_score THEN 1 
                ELSE 0 
            END) as draws,
            -- Calculate losses
            SUM(CASE 
                WHEN (m.home_team_id = t.id AND m.home_score < m.away_score) OR 
                     (m.away_team_id = t.id AND m.away_score < m.home_score) THEN 1 
                ELSE 0 
            END) as losses,
            -- Goals for
            SUM(CASE 
                WHEN m.home_team_id = t.id THEN m.home_score 
                ELSE m.away_score 
            END) as goals_for,
            -- Goals against
            SUM(CASE 
                WHEN m.home_team_id = t.id THEN m.away_score 
                ELSE m.home_score 
            END) as goals_against
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season
          AND m.status = 'FINISHED'
        GROUP BY t.id
    ),
    table_data AS (
        SELECT 
            team_name,
            team_code,
            played,
            wins,
            draws,
            losses,
            goals_for,
            goals_against,
            (goals_for - goals_against) as goal_difference,
            (wins * 3 + draws) as points
        FROM team_stats
    )
    SELECT 
        ROW_NUMBER() OVER (ORDER BY points DESC, goal_difference DESC, goals_for DESC) as pos,
        team_name as 'Team',
        played as 'P',
        wins as 'W',
        draws as 'D', 
        losses as 'L',
        goals_for as 'GF',
        goals_against as 'GA',
        goal_difference as 'GD',
        points as 'Pts',
        CASE 
            WHEN ROW_NUMBER() OVER (ORDER BY points DESC, goal_difference DESC, goals_for DESC) <= 4 THEN 'UCL ✅'
            WHEN ROW_NUMBER() OVER (ORDER BY points DESC, goal_difference DESC, goals_for DESC) = 5 THEN 'UEL ✅'
            WHEN ROW_NUMBER() OVER (ORDER BY points DESC, goal_difference DESC, goals_for DESC) BETWEEN 6 AND 7 THEN 'UECL ⚽'
            WHEN ROW_NUMBER() OVER (ORDER BY points DESC, goal_difference DESC, goals_for DESC) >= 18 THEN 'REL ❌'
            ELSE '----'
        END as 'European/Rel'
    FROM table_data
    ORDER BY points DESC, goal_difference DESC, goals_for DESC;
    ") || return 1

    if [ -t 1 ]; then
        printf '%s\n' "$table_output" | awk \
            -v top_color=$'\033[38;2;255;248;220m' \
            -v middle_color=$'\033[1;38;2;255;255;255m' \
            -v fifth_color=$'\033[38;2;155;160;170m' \
            -v reset=$'\033[0m' '
            /^ *[0-9]+  / {
                position = $0
                sub(/^[[:space:]]*/, "", position)
                sub(/[^0-9].*/, "", position)
                position += 0
                if (position >= 1 && position <= 4) print top_color $0 reset
                else if (position >= 5 && position <= 16) print middle_color $0 reset
                else if (position >= 17) print fifth_color $0 reset
                else print
                next
            }
            { print }
        '
    else
        printf '%s\n' "$table_output"
    fi
    
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "📊 KEY:"
    echo "   UCL ✅ = Champions League | UEL ✅ = Europa League | UECL ⚽ = Conference League"
    echo "   REL ❌ = Relegation"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

show_season_table_with_home_away() {
    local season="${1:-2023}"
    
    log_info "Generating detailed EPL table for season: $season"
    
    echo
    echo "══════════════════════════════════════════════════════════════════════════════════════════════"
    echo "                        PREMIER LEAGUE DETAILED TABLE $season/$((season + 1))"
    echo "══════════════════════════════════════════════════════════════════════════════════════════════"
    
    sqlite3 -header -column "$DB_FILE" "
    WITH home_stats AS (
        SELECT 
            t.id as team_id,
            t.name as team_name,
            COUNT(*) as home_played,
            SUM(CASE WHEN m.home_score > m.away_score THEN 1 ELSE 0 END) as home_wins,
            SUM(CASE WHEN m.home_score = m.away_score THEN 1 ELSE 0 END) as home_draws,
            SUM(CASE WHEN m.home_score < m.away_score THEN 1 ELSE 0 END) as home_losses,
            SUM(m.home_score) as home_goals_for,
            SUM(m.away_score) as home_goals_against
        FROM matches m
        JOIN teams t ON m.home_team_id = t.id
        WHERE m.season_id = $season
          AND m.status = 'FINISHED'
        GROUP BY t.id
    ),
    away_stats AS (
        SELECT 
            t.id as team_id,
            t.name as team_name,
            COUNT(*) as away_played,
            SUM(CASE WHEN m.away_score > m.home_score THEN 1 ELSE 0 END) as away_wins,
            SUM(CASE WHEN m.away_score = m.home_score THEN 1 ELSE 0 END) as away_draws,
            SUM(CASE WHEN m.away_score < m.home_score THEN 1 ELSE 0 END) as away_losses,
            SUM(m.away_score) as away_goals_for,
            SUM(m.home_score) as away_goals_against
        FROM matches m
        JOIN teams t ON m.away_team_id = t.id
        WHERE m.season_id = $season
          AND m.status = 'FINISHED'
        GROUP BY t.id
    ),
    combined_stats AS (
        SELECT 
            COALESCE(h.team_id, a.team_id) as team_id,
            COALESCE(h.team_name, a.team_name) as team_name,
            COALESCE(h.home_played, 0) + COALESCE(a.away_played, 0) as played,
            COALESCE(h.home_wins, 0) + COALESCE(a.away_wins, 0) as wins,
            COALESCE(h.home_draws, 0) + COALESCE(a.away_draws, 0) as draws,
            COALESCE(h.home_losses, 0) + COALESCE(a.away_losses, 0) as losses,
            COALESCE(h.home_goals_for, 0) + COALESCE(a.away_goals_for, 0) as goals_for,
            COALESCE(h.home_goals_against, 0) + COALESCE(a.away_goals_against, 0) as goals_against,
            -- Home stats
            COALESCE(h.home_played, 0) as home_played,
            COALESCE(h.home_wins, 0) as home_wins,
            COALESCE(h.home_draws, 0) as home_draws,
            COALESCE(h.home_losses, 0) as home_losses,
            COALESCE(h.home_goals_for, 0) as home_goals_for,
            COALESCE(h.home_goals_against, 0) as home_goals_against,
            -- Away stats
            COALESCE(a.away_played, 0) as away_played,
            COALESCE(a.away_wins, 0) as away_wins,
            COALESCE(a.away_draws, 0) as away_draws,
            COALESCE(a.away_losses, 0) as away_losses,
            COALESCE(a.away_goals_for, 0) as away_goals_for,
            COALESCE(a.away_goals_against, 0) as away_goals_against
        FROM home_stats h
        FULL OUTER JOIN away_stats a ON h.team_id = a.team_id
    )
    SELECT 
        ROW_NUMBER() OVER (ORDER BY (wins * 3 + draws) DESC, (goals_for - goals_against) DESC, goals_for DESC) as pos,
        team_name as 'Team',
        played as 'P',
        wins as 'W',
        draws as 'D',
        losses as 'L',
        goals_for as 'GF',
        goals_against as 'GA',
        (goals_for - goals_against) as 'GD',
        (wins * 3 + draws) as 'Pts',
        home_wins || '-' || home_draws || '-' || home_losses as 'Home',
        away_wins || '-' || away_draws || '-' || away_losses as 'Away',
        ROUND((wins * 100.0 / played), 1) || '%' as 'Win %'
    FROM combined_stats
    ORDER BY (wins * 3 + draws) DESC, (goals_for - goals_against) DESC, goals_for DESC;
    "
    
    echo
    echo "══════════════════════════════════════════════════════════════════════════════════════════════"
}

show_season_top_scorers() {
    local season="${1:-2023}"
    
    log_info "Showing goal statistics for season: $season"
    
    # Note: This shows team goals, not individual player goals
    # (We don't have player data in our schema)
    
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                         GOAL STATISTICS $season/$((season + 1))"
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    echo
    echo "🏆 TOP SCORING TEAMS:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SUM(CASE 
            WHEN m.home_team_id = t.id THEN m.home_score 
            ELSE m.away_score 
        END) DESC) as pos,
        t.name as 'Team',
        SUM(CASE 
            WHEN m.home_team_id = t.id THEN m.home_score 
            ELSE m.away_score 
        END) as 'Goals',
        ROUND(AVG(CASE 
            WHEN m.home_team_id = t.id THEN m.home_score 
            ELSE m.away_score 
        END), 2) as 'Avg/Game'
    FROM matches m
    JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
    WHERE m.season_id = $season
      AND m.status = 'FINISHED'
    GROUP BY t.id
    ORDER BY Goals DESC
    LIMIT 10;
    "
    
    echo
    echo "🛡️ BEST DEFENSES:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        ROW_NUMBER() OVER (ORDER BY SUM(CASE 
            WHEN m.home_team_id = t.id THEN m.away_score 
            ELSE m.home_score 
        END) ASC) as pos,
        t.name as 'Team',
        SUM(CASE 
            WHEN m.home_team_id = t.id THEN m.away_score 
            ELSE m.home_score 
        END) as 'Goals Conceded',
        ROUND(AVG(CASE 
            WHEN m.home_team_id = t.id THEN m.away_score 
            ELSE m.home_score 
        END), 2) as 'Avg/Game'
    FROM matches m
    JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
    WHERE m.season_id = $season
      AND m.status = 'FINISHED'
    GROUP BY t.id
    ORDER BY \"Goals Conceded\" ASC
    LIMIT 10;
    "
    
    echo
    echo "⚽ HIGHEST SCORING MATCHES:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        m.match_date as 'Date',
        ht.name as 'Home',
        m.home_score || ' - ' || m.away_score as 'Score',
        at.name as 'Away',
        (m.home_score + m.away_score) as 'Total Goals'
    FROM matches m
    JOIN teams ht ON m.home_team_id = ht.id
    JOIN teams at ON m.away_team_id = at.id
    WHERE m.season_id = $season
      AND m.status = 'FINISHED'
    ORDER BY (m.home_score + m.away_score) DESC, m.match_date DESC
    LIMIT 5;
    "
}

show_season_form_guide() {
    local season="${1:-2023}"
    local matches="${2:-5}"
    
    log_info "Showing form guide for season: $season (last $matches matches)"
    
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                      FORM GUIDE $season/$((season + 1)) (Last $matches Matches)"
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    sqlite3 -header -column "$DB_FILE" "
    WITH recent_matches AS (
        SELECT 
            t.id as team_id,
            t.name as team_name,
            m.match_date,
            CASE 
                WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR 
                     (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 'W'
                WHEN m.home_score = m.away_score THEN 'D'
                ELSE 'L'
            END as result,
            CASE 
                WHEN m.home_team_id = t.id THEN 'H'
                ELSE 'A'
            END as venue,
            ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY m.match_date DESC) as rn
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season
          AND m.status = 'FINISHED'
    ),
    form_strings AS (
        SELECT 
            team_name,
            GROUP_CONCAT(
                CASE 
                    WHEN result = 'W' THEN '✅'
                    WHEN result = 'D' THEN '⚫' 
                    WHEN result = 'L' THEN '❌'
                END,
                ' ' ORDER BY rn DESC
            ) as form,
            SUM(CASE WHEN result = 'W' THEN 1 ELSE 0 END) as wins,
            SUM(CASE WHEN result = 'D' THEN 1 ELSE 0 END) as draws,
            SUM(CASE WHEN result = 'L' THEN 1 ELSE 0 END) as losses
        FROM recent_matches
        WHERE rn <= $matches
        GROUP BY team_id, team_name
    ),
    table_positions AS (
        SELECT 
            t.id as team_id,
            t.name as team_name,
            ROW_NUMBER() OVER (
                ORDER BY 
                    SUM(CASE 
                        WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR 
                             (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 3
                        WHEN m.home_score = m.away_score THEN 1
                        ELSE 0
                    END) DESC,
                    SUM(CASE 
                        WHEN m.home_team_id = t.id THEN m.home_score - m.away_score
                        ELSE m.away_score - m.home_score
                    END) DESC,
                    SUM(CASE 
                        WHEN m.home_team_id = t.id THEN m.home_score
                        ELSE m.away_score
                    END) DESC
            ) as position
        FROM matches m
        JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
        WHERE m.season_id = $season
          AND m.status = 'FINISHED'
        GROUP BY t.id
    )
    SELECT 
        tp.position as 'Pos',
        tp.team_name as 'Team',
        fs.form as 'Form',
        fs.wins as 'W',
        fs.draws as 'D',
        fs.losses as 'L',
        ROUND((fs.wins * 100.0 / $matches), 1) || '%' as 'Win %'
    FROM table_positions tp
    JOIN form_strings fs ON tp.team_name = fs.team_name
    ORDER BY tp.position;
    "
}

show_season_summary() {
    local season="${1:-2023}"
    
    log_info "Showing season summary for: $season"
    
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                      SEASON $season/$((season + 1)) SUMMARY"
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    # Season statistics
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        'Matches Played' as 'Statistic',
        COUNT(*) as 'Value'
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED'
    
    UNION ALL
    
    SELECT 
        'Total Goals',
        SUM(home_score + away_score)
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED'
    
    UNION ALL
    
    SELECT 
        'Average Goals/Match',
        ROUND(AVG(home_score + away_score), 2)
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED'
    
    UNION ALL
    
    SELECT 
        'Home Wins',
        COUNT(*) || ' (' || ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM matches WHERE season_id = $season AND status = 'FINISHED'), 1) || '%)'
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED'
      AND home_score > away_score
    
    UNION ALL
    
    SELECT 
        'Away Wins',
        COUNT(*) || ' (' || ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM matches WHERE season_id = $season AND status = 'FINISHED'), 1) || '%)'
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED'
      AND away_score > home_score
    
    UNION ALL
    
    SELECT 
        'Draws',
        COUNT(*) || ' (' || ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM matches WHERE season_id = $season AND status = 'FINISHED'), 1) || '%)'
    FROM matches 
    WHERE season_id = $season 
      AND status = 'FINISHED'
      AND home_score = away_score;
    "
    
    echo
    echo "👑 CHAMPIONS:"
    sqlite3 -header -column "$DB_FILE" "
    SELECT 
        t.name as 'Team',
        SUM(CASE 
            WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR 
                 (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 3
            WHEN m.home_score = m.away_score THEN 1
            ELSE 0
        END) as 'Points',
        SUM(CASE 
            WHEN (m.home_team_id = t.id AND m.home_score > m.away_score) OR 
                 (m.away_team_id = t.id AND m.away_score > m.home_score) THEN 1
            ELSE 0
        END) as 'Wins'
    FROM matches m
    JOIN teams t ON (t.id = m.home_team_id OR t.id = m.away_team_id)
    WHERE m.season_id = $season
      AND m.status = 'FINISHED'
    GROUP BY t.id
    ORDER BY Points DESC
    LIMIT 1;
    "
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    
    case "${1:-table}" in
        "table")
            show_season_table "${2:-2023}"
            ;;
        "detailed")
            show_season_table_with_home_away "${2:-2023}"
            ;;
        "goals")
            show_season_top_scorers "${2:-2023}"
            ;;
        "form")
            show_season_form_guide "${2:-2023}" "${3:-5}"
            ;;
        "summary")
            show_season_summary "${2:-2023}"
            ;;
        "all")
            show_season_table "${2:-2023}"
            echo
            show_season_form_guide "${2:-2023}" 5
            echo
            show_season_top_scorers "${2:-2023}"
            ;;
        "help")
            echo "Usage: $0 {table|detailed|goals|form|summary|all} [season_year]"
            echo ""
            echo "Commands:"
            echo "  table [year]     - Show standard league table (default: 2023)"
            echo "  detailed [year]  - Show table with home/away splits"
            echo "  goals [year]     - Show goal statistics"
            echo "  form [year] [n]  - Show form guide for last n matches (default: 5)"
            echo "  summary [year]   - Show season summary"
            echo "  all [year]       - Show all statistics"
            echo ""
            echo "Examples:"
            echo "  $0 table 2022     # Show 2022/23 season table"
            echo "  $0 detailed       # Show detailed table for current/last season"
            echo "  $0 form 2023 10   # Show last 10 matches form for 2023/24"
            ;;
        *)
            show_season_table "${1:-2023}"
            ;;
    esac
fi
