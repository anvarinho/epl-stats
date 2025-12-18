#!/bin/bash

# Configuration for EPL Data Collection System (macOS compatible)
set -e

# API Configuration
export API_BASE="https://api.football-data.org/v4"
export API_TOKEN="acb443dbb70c4852b1958b034cdafac6"

# Database Configuration
export DB_FILE="${DB_FILE:-epl_data.db}"
export LOG_FILE="${LOG_FILE:-epl_etl.log}"

# EPL Competition ID (Premier League)
export COMPETITION_ID="PL"

# Current season (will be set dynamically)
CURRENT_SEASON=$(date +"%Y")

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "jq" "sqlite3")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Missing dependency: $dep"
            exit 1
        fi
    done
    log_success "All dependencies available"
}

# macOS compatible function to extract HTTP status and content
extract_http_response() {
    local response="$1"
    local temp_file=$(mktemp)
    echo "$response" > "$temp_file"
    
    # Extract HTTP status code (last line)
    local http_code=$(tail -n 1 "$temp_file")
    
    # Extract content (all but last line)
    local content
    if [ "$(wc -l < "$temp_file")" -gt 1 ]; then
        content=$(head -n -1 "$temp_file")
    else
        content=""
    fi
    
    rm -f "$temp_file"
    echo "$content"
    return "$http_code"
}

# API call with retry logic (macOS compatible)
api_call() {
    local endpoint="$1"
    local max_retries=3
    local retry_count=0
    local wait_time=5
    
    while [ $retry_count -lt $max_retries ]; do
        local temp_file=$(mktemp)
        
        # Make API call with verbose output to capture headers
        local http_code
        http_code=$(curl -s -w "%{http_code}" \
            -H "X-Auth-Token: $API_TOKEN" \
            -o "$temp_file" \
            "$API_BASE/$endpoint")
        
        local content
        content=$(cat "$temp_file")
        rm -f "$temp_file"
        
        if [ "$http_code" -eq 200 ]; then
            echo "$content"
            return 0
        elif [ "$http_code" -eq 429 ]; then
            log_warning "Rate limit hit, waiting ${wait_time}s..."
            sleep $wait_time
            wait_time=$((wait_time * 2))
        else
            log_error "API call failed with HTTP $http_code for endpoint: $endpoint"
            if [ -n "$content" ]; then
                log_error "API response: $content"
            fi
            retry_count=$((retry_count + 1))
            sleep $wait_time
        fi
    done
    
    log_error "Failed after $max_retries attempts for endpoint: $endpoint"
    return 1
}

# Test API connectivity
test_api_connection() {
    log_info "Testing API connection..."
    local response
    response=$(api_call "competitions/$COMPETITION_ID")
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        local comp_name=$(echo "$response" | jq -r '.name // "Unknown"')
        log_success "API connection successful - Connected to: $comp_name"
        return 0
    else
        log_error "API connection failed"
        return 1
    fi
}
