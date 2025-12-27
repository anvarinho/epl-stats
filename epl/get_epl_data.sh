#!/bin/bash

# Simple EPL data fetcher
# Make sure config.sh is sourced first or run: source config.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}EPL Data Fetcher${NC}"
echo "=================="

# Function to fetch data
fetch_data() {
    local endpoint=$1
    local output_file=$2
    
    echo -e "\n${GREEN}Fetching: $endpoint${NC}"
    
    curl -s -H "X-Auth-Token: $API_TOKEN" \
         "$API_BASE/$endpoint" \
         | python3 -m json.tool > "$output_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ Data saved to: $output_file"
        echo "📄 First 5 lines:"
        head -5 "$output_file"
    else
        echo -e "${RED}❌ Failed to fetch data${NC}"
    fi
}

# Main menu
while true; do
    echo -e "\n${BLUE}Select option:${NC}"
    echo "1) Get EPL standings"
    echo "2) Get today's matches"
    echo "3) Get all EPL teams"
    echo "4) Get competition info"
    echo "5) Get specific match"
    echo "6) Exit"
    
    read -p "Enter choice (1-6): " choice
    
    case $choice in
        1)
            fetch_data "competitions/PL/standings" "standings.json"
            ;;
        2)
            fetch_data "matches?competitions=PL&dateFrom=$(date +%Y-%m-%d)&dateTo=$(date +%Y-%m-%d)" "today_matches.json"
            ;;
        3)
            fetch_data "competitions/PL/teams" "teams.json"
            ;;
        4)
            fetch_data "competitions/PL" "competition.json"
            ;;
        5)
            read -p "Enter match ID: " match_id
            fetch_data "matches/$match_id" "match_$match_id.json"
            ;;
        6)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
done
