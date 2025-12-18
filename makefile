# EPL Data Collection System Makefile

.PHONY: all init backfill daily stats clean help

DB_FILE ?= epl_data.db

all: init backfill

init:
	@echo "Initializing database..."
	@chmod +x init_db.sh
	@./init_db.sh

backfill:
	@echo "Starting historical data backfill..."
	@chmod +x collect_data.sh
	@./collect_data.sh backfill

daily:
	@echo "Fetching daily updates..."
	@chmod +x collect_data.sh
	@./collect_data.sh daily

season:
	@echo "Fetching specific season: $(YEAR)"
	@chmod +x collect_data.sh
	@./collect_data.sh season $(YEAR)

stats:
	@echo "Showing database statistics..."
	@chmod +x inspect_db.sh
	@./inspect_db.sh stats

team:
	@echo "Showing matches for team: $(NAME)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh team "$(NAME)"

clean:
	@echo "Cleaning up..."
	@rm -f $(DB_FILE) $(LOG_FILE)

help:
	@echo "EPL Data Collection System"
	@echo ""
	@echo "Available commands:"
	@echo "  make init        - Initialize database"
	@echo "  make backfill    - Backfill 5 years of historical data"
	@echo "  make daily       - Fetch daily updates"
	@echo "  make season YEAR=2023 - Fetch specific season"
	@echo "  make stats       - Show database statistics"
	@echo "  make team NAME='Team Name' - Show team matches"
	@echo "  make clean       - Remove database and logs"


# Add these to your Makefile
next:
	@echo "Showing next game for team: $(NAME)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh next "$(NAME)"

fixtures:
	@echo "Showing upcoming fixtures for team: $(NAME)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh fixtures "$(NAME)"

analytics:
	@echo "Showing analytics for team: $(NAME)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh analytics "$(NAME)"

form:
	@echo "Showing recent form for team: $(NAME)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh form "$(NAME)"
	

# Add to Makefile
head2head:
	@echo "Showing head-to-head between: $(TEAM1) vs $(TEAM2)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh head2head "$(TEAM1)" "$(TEAM2)"

h2h:
	@echo "Showing detailed head-to-head: $(TEAM1) vs $(TEAM2)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh h2h "$(TEAM1)" "$(TEAM2)"

# Add to Makefile
predict:
	@echo "Generating prediction for: $(TEAM1) vs $(TEAM2)"
	@chmod +x inspect_db.sh
	@./inspect_db.sh predict "$(TEAM1)" "$(TEAM2)"

predictions:
	@echo "Generating predictions for next matchday"
	@chmod +x inspect_db.sh
	@./inspect_db.sh predictions

# Add to Makefile
table:
	@echo "Showing EPL table for season: $(SEASON)"
	@chmod +x epl_table.sh
	@./epl_table.sh table $(SEASON)

epl-stats:
	@echo "Showing EPL statistics for season: $(SEASON)"
	@chmod +x epl_table.sh
	@./epl_table.sh all $(SEASON)

epl-form:
	@echo "Showing EPL form guide for season: $(SEASON)"
	@chmod +x epl_table.sh
	@./epl_table.sh form $(SEASON) $(MATCHES)

# Add to Makefile
force-update:
	@echo "Force updating recent matches..."
	@chmod +x collect_data.sh
	@./collect_data.sh force-update $(DAYS)

fix-scores:
	@echo "Checking and fixing missing scores..."
	@chmod +x collect_data.sh
	@./collect_data.sh fix-scores

verify-updates:
	@echo "Verifying recent updates..."
	@sqlite3 $(DB_FILE) "
	SELECT 
	    m.match_date as date,
	    ht.name as home,
	    m.home_score || ' - ' || m.away_score as score,
	    at.name as away,
	    m.status,
	    m.last_updated
	FROM matches m
	JOIN teams ht ON m.home_team_id = ht.id
	JOIN teams at ON m.away_team_id = at.id
	WHERE date(m.last_updated) = date('now')
	   OR m.match_date >= date('now', '-3 days')
	ORDER BY m.last_updated DESC
	LIMIT 10;
	"
