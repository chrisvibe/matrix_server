#!/bin/bash

# Matrix Admin CLI - Simple & Clean

# Load environment variables from parent directory .env
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Configuration from environment
MATRIX_SERVER="${MATRIX_SERVER}"
MATRIX_DOMAIN="${MATRIX_DOMAIN}"
DEFAULT_USER="${MATRIX_ADMIN_USER}"

# Token storage in user's config directory
CONFIG_DIR="${HOME}/.config/matrix"
TOKEN_FILE="${CONFIG_DIR}/token"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${1}${2}${NC}"; }

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

cleanup() { 
    # Only cleanup on script exit, not between commands
    :
}
trap cleanup EXIT

save_token() { 
    echo "$1" > "$TOKEN_FILE" && chmod 600 "$TOKEN_FILE"
    print_status $GREEN "Session saved to $TOKEN_FILE"
}

load_token() { 
    [ -f "$TOKEN_FILE" ] && cat "$TOKEN_FILE"
}

clear_token() {
    rm -f "$TOKEN_FILE" 2>/dev/null
    print_status $GREEN "Session cleared"
}

get_token() {
    local user=${1:-$DEFAULT_USER}
    local password=$2
    
    local existing_token=$(load_token)
    if [ -n "$existing_token" ]; then
        print_status $GREEN "Using existing session"
        echo "$existing_token"
        return 0
    fi
    
    [ -z "$password" ] && { echo -n "Password for $user: "; read -s password; echo; }
    
    print_status $YELLOW "Getting admin token for $user..."
    
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"type\": \"m.login.password\", \"user\": \"$user\", \"password\": \"$password\"}" \
        "$MATRIX_SERVER/_matrix/client/r0/login")
    
    if echo "$response" | grep -q "access_token"; then
        local token=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
        save_token "$token"
        print_status $GREEN "✅ Token obtained"
        echo "$token"
    else
        print_status $RED "❌ Login failed"
        return 1
    fi
}

generate_reg_token() {
    local admin_token=${1:-$(load_token)}
    local uses_allowed=${2:-2}
    local days=${3:-3}
    
    [ -z "$admin_token" ] && { print_status $RED "No token. Run 'get_token' first"; return 1; }
    
    local expiry_time=$(date -d "+${days} days" +%s000)
    
    print_status $YELLOW "Generating registration token (${uses_allowed} uses, ${days} days)..."
    
    local response=$(curl -s -X POST -H "Authorization: Bearer $admin_token" \
        -H "Content-Type: application/json" \
        -d "{\"uses_allowed\": $uses_allowed, \"expiry_time\": $expiry_time}" \
        "$MATRIX_SERVER/_synapse/admin/v1/registration_tokens/new")
    
    if echo "$response" | grep -q "token"; then
        local reg_token=$(echo "$response" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
        print_status $GREEN "Registration token: $reg_token"
        print_status $GREEN "Share URL: $MATRIX_SERVER/matrix/#/register?token=$reg_token"
    else
        print_status $RED "❌ Failed to create token"
        return 1
    fi
}

check_token_status() {
    local admin_token=${1:-$(load_token)}
    local filter="$2"
    [ -z "$admin_token" ] && { print_status $RED "No token. Run 'get_token' first"; return 1; }
    
    local url="$MATRIX_SERVER/_synapse/admin/v1/registration_tokens"
    [ "$filter" = "active" ] && url="${url}?valid=true"
    [ "$filter" = "expired" ] && url="${url}?valid=false"
    
    curl -s -H "Authorization: Bearer $admin_token" "$url" | \
        python3 -m json.tool 2>/dev/null || echo "Install python3 for pretty JSON"
}

check_user() {
    local admin_token=${1:-$(load_token)}
    local username=$2
    [ -z "$admin_token" ] && { print_status $RED "No token. Run 'get_token' first"; return 1; }
    
    [ -z "$username" ] && username="@${DEFAULT_USER}:${MATRIX_DOMAIN}"
    [[ ! "$username" =~ ^@ ]] && username="@${username}:${MATRIX_DOMAIN}"
    
    curl -s -H "Authorization: Bearer $admin_token" \
        "$MATRIX_SERVER/_synapse/admin/v2/users/$username" | \
        python3 -m json.tool 2>/dev/null || echo "Install python3 for pretty JSON"
}

list_users() {
    local admin_token=${1:-$(load_token)}
    local limit=${2:-100}
    [ -z "$admin_token" ] && { print_status $RED "No token. Run 'get_token' first"; return 1; }
    
    curl -s -H "Authorization: Bearer $admin_token" \
        "$MATRIX_SERVER/_synapse/admin/v2/users?limit=$limit" | \
        python3 -m json.tool 2>/dev/null || echo "Install python3 for pretty JSON"
}

show_config() {
    print_status $BLUE "Server: $MATRIX_SERVER"
    print_status $BLUE "Domain: $MATRIX_DOMAIN" 
    print_status $BLUE "User: $DEFAULT_USER"
    print_status $BLUE "Token file: $TOKEN_FILE"
    local token=$(load_token)
    [ -n "$token" ] && print_status $GREEN "Session: Active" || print_status $YELLOW "Session: None"
}

set_server() {
    local new_server="$1"
    local new_domain="${2:-$(echo "$new_server" | sed 's|https\?://||' | sed 's|/.*||')}"
    
    [ -z "$new_server" ] && { print_status $RED "Usage: set_server <url> [domain]"; return 1; }
    
    MATRIX_SERVER="$new_server"
    MATRIX_DOMAIN="$new_domain"
    clear_token # Clear old token when changing servers
    
    print_status $GREEN "Server: $MATRIX_SERVER"
    print_status $GREEN "Domain: $MATRIX_DOMAIN"
}

run_cmd() {
    local exit_code=0
    case "$1" in
        get_token|login) get_token "${@:2}" || exit_code=1 ;;
        logout) clear_token ;;
        gen*) generate_reg_token "" "${@:2}" || exit_code=1 ;;
        status) check_token_status || exit_code=1 ;;
        user) check_user "" "$2" || exit_code=1 ;;
        users) list_users "" "$2" || exit_code=1 ;;
        conf*) show_config ;;
        set_server) set_server "${@:2}" || exit_code=1 ;;
        help|h) 
            echo "Commands: login, logout, gen [uses] [days], status [active|expired], user [name], users [limit]"
            echo "          expired, conf, set_server <url>, help, exit"
            echo
            echo "Quick start:"
            echo "  1. login             # Login as admin first"
            echo "  2. gen 5 7           # Create registration token (5 uses, 7 days)"
            echo "  3. status active     # Check only active tokens"
            echo "  4. logout            # Clear session token"
            ;;
        exit|quit|q) return 1 ;;
        "") ;;
        *) print_status $RED "Unknown: $1. Type 'help'"; exit_code=1 ;;
    esac
    return 0  # Don't exit interactive mode on command errors
}

interactive() {
    print_status $GREEN "=== Matrix Admin ==="
    show_config
    echo
    
    [ -n "$1" ] && get_token "$DEFAULT_USER" "$1"
    
    while true; do
        printf "%bmatrix>%b " "$GREEN" "$NC"
        read -r line || break
        
        [ -n "$line" ] && {
            set -- $line
            run_cmd "$@" || break
        }
    done
    
    print_status $GREEN "Goodbye!"
}

# Main
case "${1:-help}" in
    interactive|i) interactive "$2" ;;
    get_token|login) get_token "$2" "$3" ;;
    logout) clear_token ;;
    generate_reg_token) generate_reg_token "" "$2" "$3" ;;
    check_token_status) check_token_status "" "$2" ;;
    expired) check_token_status "" "expired" ;;
    check_user) check_user "" "$2" ;;
    list_users) list_users "" "$2" ;;
    *)
        echo "Matrix Admin CLI"
        echo "Usage: $0 interactive [password]"
        echo "   Or: $0 <command> [args]"
        echo
        echo "Commands: login, logout, generate_reg_token, check_token_status, check_user, list_users"
        echo "Tip: Use interactive mode!"
        ;;
esac
