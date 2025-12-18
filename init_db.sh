#!/bin/bash

# Initialize the SQLite database with schema
source config.sh

init_database() {
    log_info "Initializing database: $DB_FILE"
    
    if [ -f "$DB_FILE" ]; then
        log_warning "Database already exists at $DB_FILE"
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm "$DB_FILE"
        else
            log_info "Using existing database"
            return 0
        fi
    fi
    
    # Create database with schema
    if sqlite3 "$DB_FILE" < schema.sql; then
        log_success "Database initialized successfully"
        
        # Insert recent seasons (last 5 years)
        local current_year=$(date +"%Y")
        for year in $(seq $((current_year - 4)) $current_year); do
            local season_start="$year-08-01"
            local season_end="$((year + 1))-05-31"
            local is_current=$((year == current_year ? 1 : 0))
            
            sqlite3 "$DB_FILE" <<EOF
INSERT OR IGNORE INTO seasons (id, start_date, end_date, current) 
VALUES ($year, '$season_start', '$season_end', $is_current);
EOF
        done
        log_success "Seasons data inserted"
    else
        log_error "Failed to initialize database"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    init_database
fi
