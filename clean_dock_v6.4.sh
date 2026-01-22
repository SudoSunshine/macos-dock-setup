#!/usr/bin/env bash
# shellcheck disable=SC2329
#
# Dock App Management for Jamf Pro
# Version: 6.4-PRODUCTION
# Last Updated: January 22, 2026
#
# Author: Ellie Romero
# Email: ellie.romero@jamf.com
#
# Description:
#   Enterprise-grade macOS Dock management script for Jamf Pro environments.
#   Clears the Dock and adds specified applications using bundle identifiers.
#   
#   Capabilities:
#     • Adds up to 8 apps via Jamf Pro parameters 4-11 (GUI limit)
#     • Preserves Dock folders, settings, and user preferences
#     • Automatically detects and resolves app symlinks (no alias arrows)
#     • Normalizes paths for clean, professional Dock entries
#     • Falls back from Self Service+ to classic Self Service automatically
#     • Works on fresh Mac enrollments without Command Line Developer Tools
#     • Zero external dependencies (pure bash using native macOS commands)
#   
#   Use Cases:
#     • Standardize Dock across departments or roles
#     • New Mac onboarding and setup automation
#     • User migration or computer refresh workflows
#     • Self-Service Dock reset policies
#
# Features:
#   - Pure bash implementation (no Python, Perl, or external tools)
#   - Works on fresh Mac enrollments without Command Line Tools
#   - Automatic Self Service+ to classic Self Service fallback
#   - Symlink detection and resolution (prevents alias arrows)
#   - Path normalization (removes .. components for clean paths)
#   - Double-fallback app discovery (mdfind + find)
#   - Comprehensive error handling and logging
#   - Lock file protection (prevents concurrent execution)
#   - Timeout protection on all operations
#   - ShellCheck compliant code
#
set -euo pipefail

################################################################################
# JAMF PRO PARAMETERS - CONFIGURE YOUR APPS HERE
################################################################################
#
# Parameter 4:  First app bundle ID
#               Example: com.microsoft.Outlook
#
# Parameter 5:  Second app bundle ID
#               Example: com.google.Chrome
#
# Parameter 6:  Third app bundle ID
#               Example: com.tinyspeck.slackmacgap
#
# Parameter 7:  Fourth app bundle ID
#               Example: com.apple.dt.Xcode
#
# Parameter 8:  Fifth app bundle ID
#               Example: com.jamfsoftware.selfservice.mac
#
# Parameter 9:  Sixth app bundle ID
#               Example: com.openai.chat
#
# Parameter 10: Seventh app bundle ID
#               Example: com.apple.Safari
#
# Parameter 11: Eighth app bundle ID
#               Example: com.apple.mail
#
# Notes:
#       - Parameters 1-3 are reserved by Jamf Pro (target drive, computer name, username)
#       - Parameters 4-11 give you 8 app slots (recommended for most deployments)
#       - Finder is automatically added by macOS as the first Dock item
#       - Leave unused parameters empty
#
# ADVANCED: Extending Beyond 8 Apps
#       The Jamf Pro GUI limits parameters to 11, providing 8 app slots (params 4-11).
#       Most users find 8 apps sufficient, but power users can extend this limit.
#
#       STEP-BY-STEP INSTRUCTIONS TO EXTEND:
#       
#       Step 1: Increase Parameter Limit
#         • Locate: Line ~452 (search for: "if (( last > 11 )); then")
#         • Change: "last=11" to your desired limit
#         • Example: "last=20" allows 17 apps (parameters 4-20)
#       
#       Step 2: Update Warning Message
#         • Locate: Line ~512 (search for: "Only parameters 4-11 processed")
#         • Change: "4-11" to match your new limit
#         • Example: "Only parameters 4-20 processed; extras ignored"
#       
#       Step 3: Pass Additional Parameters
#         • Option A: Use Jamf Pro API to add parameters beyond 11
#         • Option B: Call script directly via policy with extra arguments
#         • Option C: Create custom policy with extended parameter support
#       
#       WARNING: More than 10-12 apps can clutter the Dock and impact UX.
#       Consider using multiple policies for different user roles instead.
#
################################################################################

################################################################################
# SCRIPT CONFIGURATION
################################################################################

readonly LOGTAG="clean_dock"
readonly SCRIPT_VERSION="6.4-production"
readonly LOCKFILE_DIR="/tmp"
readonly TIMEOUT_DEFAULT=30
readonly TIMEOUT_SHORT=10

# Validation patterns
readonly USERNAME_REGEX='^[a-zA-Z0-9_.-]+$'
readonly BUNDLE_ID_REGEX='^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$'
# shellcheck disable=SC2016
readonly DANGEROUS_CHARS_REGEX='[;$()` |\]'

################################################################################
# 1. LOGGING FUNCTIONS
################################################################################

# 1.1 Log error message and exit
err() { 
    echo "[${LOGTAG}] ERROR: $*" >&2
    logger -t "$LOGTAG" "ERROR: $*"
    exit 1
}

# 1.2 Log informational message
log() { 
    echo "[${LOGTAG}] $*"
    logger -t "$LOGTAG" "$*"
}

# 1.3 Log warning message
warn() { 
    echo "[${LOGTAG}] WARNING: $*"
    logger -t "$LOGTAG" "WARNING: $*"
}

################################################################################
# 2. TIMEOUT FUNCTION (Bash-native, no GNU coreutils needed)
################################################################################

# 2.1 Run command with timeout
run_with_timeout() {
    local timeout=$1
    shift
    
    # Run command in background
    "$@" &
    local pid=$!
    
    # Wait for completion or timeout
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        if (( count >= timeout )); then
            kill -TERM "$pid" 2>/dev/null || true
            sleep 0.5
            kill -KILL "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        ((count++))
    done
    
    wait "$pid"
}

################################################################################
# 3. FILE LOCKING FUNCTIONS (Bash-native, no flock needed)
################################################################################

# 3.1 Acquire lock using atomic directory creation
acquire_lock() {
    local lockfile="$1"
    local max_wait=30
    local count=0
    
    while ! mkdir "$lockfile" 2>/dev/null; do
        if (( count >= max_wait )); then
            return 1
        fi
        sleep 1
        ((count++))
    done
    
    echo $$ > "$lockfile/pid"
    return 0
}

# 3.2 Release lock
release_lock() {
    local lockfile="$1"
    rm -rf "$lockfile" 2>/dev/null || true
}

################################################################################
# 4. USER MANAGEMENT FUNCTIONS
################################################################################

# 4.1 Run command as target user
run_as_user() { 
    run_with_timeout "$TIMEOUT_DEFAULT" sudo -u "$USER" env HOME="/Users/$USER" "$@"
}

################################################################################
# 5. VALIDATION FUNCTIONS
################################################################################

# 5.1 Validate bundle identifier format
validate_bundle_id() {
    local bid="$1"
    
    if [[ ! "$bid" =~ $BUNDLE_ID_REGEX ]]; then
        warn "Invalid bundle ID format: $bid"
        return 1
    fi
    
    if [[ "$bid" =~ $DANGEROUS_CHARS_REGEX ]]; then
        warn "Bundle ID contains suspicious characters: $bid"
        return 1
    fi
    
    return 0
}

################################################################################
# 6. APP DISCOVERY FUNCTIONS
################################################################################

# 6.1 Find application by bundle identifier
find_app() {
    local bid="$1"
    local result=""
    
    # Try mdfind first (fastest when Spotlight index is current)
    result=$(mdfind "kMDItemCFBundleIdentifier == '$bid'" 2>/dev/null | grep -m1 '\.app$' || true)
    
    if [[ -n "$result" && -e "$result" ]]; then
        echo "$result"
        return 0
    fi
    
    # Fallback: Manual search in common locations
    local search_paths=(
        "/Applications"
        "/System/Applications"
        "/Applications/Utilities"
        "/System/Applications/Utilities"
        "/Users/$USER/Applications"
    )
    
    for base_dir in "${search_paths[@]}"; do
        [[ -d "$base_dir" ]] || continue
        
        while IFS= read -r app_path; do
            [[ -e "$app_path" ]] || continue
            
            local info_plist="$app_path/Contents/Info.plist"
            [[ -f "$info_plist" ]] || continue
            
            local app_id
            app_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$info_plist" 2>/dev/null || true)
            
            if [[ "$app_id" == "$bid" ]]; then
                echo "$app_path"
                return 0
            fi
        done < <(find "$base_dir" -maxdepth 2 -name "*.app" -type d 2>/dev/null)
    done
    
    return 1
}

################################################################################
# 7. URL ENCODING FUNCTION
################################################################################

# 7.1 URL encode path using pure bash with lookup table (zero triggers)
url_encode() {
    local string="$1"
    local encoded=""
    local length="${#string}"
    local i c
    
    # Lookup table for common characters that need encoding
    for (( i=0; i<length; i++ )); do
        c="${string:i:1}"
        case "$c" in
            [a-zA-Z0-9./_~-])
                # Safe characters - no encoding needed
                encoded+="$c"
                ;;
            ' ')
                encoded+="%20"
                ;;
            '!')
                encoded+="%21"
                ;;
            '"')
                encoded+="%22"
                ;;
            '#')
                encoded+="%23"
                ;;
            '$')
                encoded+="%24"
                ;;
            '%')
                encoded+="%25"
                ;;
            '&')
                encoded+="%26"
                ;;
            "'")
                encoded+="%27"
                ;;
            '(')
                encoded+="%28"
                ;;
            ')')
                encoded+="%29"
                ;;
            '*')
                encoded+="%2A"
                ;;
            '+')
                encoded+="%2B"
                ;;
            ',')
                encoded+="%2C"
                ;;
            ':')
                encoded+="%3A"
                ;;
            ';')
                encoded+="%3B"
                ;;
            '=')
                encoded+="%3D"
                ;;
            '?')
                encoded+="%3F"
                ;;
            '@')
                encoded+="%40"
                ;;
            '[')
                encoded+="%5B"
                ;;
            ']')
                encoded+="%5D"
                ;;
            *)
                # For any other character, just pass through
                # (This is safe for file paths on macOS)
                encoded+="$c"
                ;;
        esac
    done
    
    echo "$encoded"
}

################################################################################
# 8. DOCK MANIPULATION FUNCTIONS
################################################################################

# 8.1 Clear all apps from Dock
clear_dock() {
    log "Clearing Dock (persistent-apps array)"
    run_as_user defaults write com.apple.dock persistent-apps -array
}

# 8.2 Add single app to Dock
add_to_dock() {
    local path="$1"
    
    if [[ ! -e "$path" ]]; then
        warn "Path does not exist: $path"
        return 1
    fi
    
    # Resolve symlinks to actual path (prevents alias arrow in Dock)
    if [[ -L "$path" ]]; then
        local real_path
        # Use readlink to resolve symlink (works on macOS)
        real_path=$(readlink "$path" 2>/dev/null)
        if [[ -n "$real_path" ]]; then
            # If relative path, make it absolute
            if [[ "$real_path" != /* ]]; then
                real_path="$(dirname "$path")/$real_path"
            fi
            log "Resolved symlink: $path -> $real_path"
            
            # Normalize path to remove .. components
            # Use cd + pwd to get clean absolute path
            local normalized_path
            if [[ -d "$real_path" ]]; then
                # For directories
                normalized_path=$(cd "$real_path" 2>/dev/null && pwd -P)
            elif [[ -e "$real_path" ]]; then
                # For files/apps: normalize directory, append filename
                local dir
                local base
                dir=$(dirname "$real_path")
                base=$(basename "$real_path")
                if [[ -d "$dir" ]]; then
                    normalized_path=$(cd "$dir" 2>/dev/null && pwd -P)/"$base"
                fi
            fi
            
            # Use normalized path if we got one, otherwise use real_path as-is
            if [[ -n "$normalized_path" && -e "$normalized_path" ]]; then
                log "Normalized to: $normalized_path"
                path="$normalized_path"
            else
                path="$real_path"
            fi
        fi
    fi
    
    local encoded_path
    encoded_path=$(url_encode "$path")
    local url="file://${encoded_path}/"
    
    if run_as_user defaults write com.apple.dock persistent-apps -array-add \
        "<dict><key>tile-data</key><dict><key>file-data</key><dict>\
<key>_CFURLString</key><string>${url}</string>\
<key>_CFURLStringType</key><integer>15</integer></dict></dict>\
<key>tile-type</key><string>file-tile</string></dict>"; then
        log "Added to Dock: $path"
        return 0
    else
        warn "Failed to add $path to Dock"
        return 1
    fi
}

################################################################################
# 9. MAIN EXECUTION
################################################################################

# 9.1 Determine and validate target user
USER="${3:-$(stat -f %Su /dev/console 2>/dev/null)}"

if [[ -z "$USER" ]]; then
    err "Cannot determine console user"
fi

if [[ "$USER" == "root" ]]; then
    err "Cannot run for root user"
fi

if [[ ! "$USER" =~ $USERNAME_REGEX ]]; then
    err "Invalid username format: $USER"
fi

if ! id "$USER" &>/dev/null; then
    err "User does not exist: $USER"
fi

log "Script version: $SCRIPT_VERSION"
log "Target user: $USER"

# 9.2 Implement lock file to prevent concurrent execution
LOCKFILE="${LOCKFILE_DIR}/clean_dock_${USER}.lock"

if ! acquire_lock "$LOCKFILE"; then
    err "Another instance is already running for user $USER (or stale lock exists)"
fi

trap 'release_lock "$LOCKFILE"' EXIT

# 9.3 Clear the Dock
clear_dock

# 9.4 Process bundle IDs from parameters 4-11 and add apps to Dock
log "Processing bundle IDs from parameters 4-11..."

last=$#
if (( last > 11 )); then
    last=11
fi

app_count=0

for (( i=4; i<=last; i++ )); do
    bid="${!i:-}"
    
    [[ -z "$bid" ]] && continue
    
    if ! validate_bundle_id "$bid"; then
        warn "Skipping invalid bundle ID at parameter $i: $bid"
        continue
    fi
    
    log "Processing parameter $i: $bid"
    
    if path=$(find_app "$bid"); then
        log "Found: $path"
        
        if [[ ! -e "$path" ]]; then
            warn "Path no longer exists: $path"
            continue
        fi
        
        if add_to_dock "$path"; then
            ((app_count++))
        fi
    else
        # App not found - check for automatic fallback options
        fallback_bid=""
        
        # Self Service+ fallback to classic Self Service
        if [[ "$bid" == "com.jamf.selfserviceplus" ]]; then
            log "Self Service+ (com.jamf.selfserviceplus) not found"
            log "Attempting fallback to classic Self Service (com.jamfsoftware.selfservice.mac)..."
            fallback_bid="com.jamfsoftware.selfservice.mac"
        fi
        
        # Try fallback bundle ID if available
        if [[ -n "$fallback_bid" ]]; then
            if path=$(find_app "$fallback_bid"); then
                log "Found fallback: $path"
                
                if [[ -e "$path" ]]; then
                    if add_to_dock "$path"; then
                        log "Successfully added fallback app to Dock"
                        ((app_count++))
                    fi
                fi
            else
                warn "Bundle ID not found: $bid (and fallback $fallback_bid also not found)"
            fi
        else
            warn "Bundle ID not found: $bid - App may not be installed or bundle ID is incorrect"
        fi
    fi
done

if (( $# > 11 )); then
    warn "Only parameters 4-11 processed; extras ignored (Jamf GUI limit)"
fi

log "Successfully added $app_count apps to Dock"

# 9.5 Restart Dock to apply changes
log "Restarting Dock for $USER"

if run_with_timeout "$TIMEOUT_SHORT" run_as_user killall Dock 2>/dev/null; then
    log "Dock restarted successfully"
else
    warn "Dock restart may have failed or timed out"
fi

log "Dock setup complete for $USER"
exit 0
