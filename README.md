# macOS Dock Management Script

Manages macOS Dock configuration for Jamf Pro environments. Clears the Dock and adds applications using bundle identifiers.

## What It Does

This script standardizes Dock layouts across Mac fleets by clearing existing apps and adding specified applications. It preserves Dock folders and user settings while replacing the app lineup.

## Features

- Zero external dependencies (pure bash)
- Works on fresh Mac enrollments without Command Line Tools
- Automatically resolves app symlinks (no alias arrows in Dock)
- Self Service+ to classic Self Service fallback
- Supports up to 8 apps via Jamf Pro GUI
- Can be extended for unlimited apps

## Quick Start

### Basic Setup in Jamf Pro

1. Upload script to Jamf Pro (Settings → Scripts)
2. Create a policy and add the script
3. Configure parameters 4-11 with bundle IDs (see examples below)
4. Scope the policy to target computers

### Parameter Examples

Configure these in your Jamf Pro policy:

```
Parameter 4: com.jamf.selfserviceplus
Parameter 5: com.apple.Safari
Parameter 6: com.apple.Terminal
Parameter 7: com.microsoft.Outlook
Parameter 8: com.tinyspeck.slackmacgap
Parameter 9: (leave empty or add another app)
```

**Note:** Parameters 1-3 are reserved by Jamf Pro. Parameters 4-11 give you 8 app slots.

## Configuration

All user-configurable options are in the script's **USER CONFIGURATION** section (lines 99-130).

### Default Setup

By default, the script uses Jamf Pro parameters 4-11 for up to 8 apps. This is perfect for most deployments and allows different apps per policy.

### Option 1: Hardcode Apps in Script

**Use when:** All Macs should have the same Dock configuration.

**How it works:** Uncomment the `HARDCODED_APPS` array at line ~112 and add your bundle IDs:

```bash
HARDCODED_APPS=(
    "com.jamf.selfserviceplus"
    "com.apple.Safari"
    "com.apple.Terminal"
    "com.microsoft.Outlook"
    "com.tinyspeck.slackmacgap"
    "com.microsoft.teams2"
    # Add as many apps as you need
)
```

**Important:** When `HARDCODED_APPS` is enabled, Jamf parameters 4-11 are ignored. This is an either/or choice.

### Option 2: Increase Parameter Limit

**Use when:** You need more than 8 apps but still want flexibility via Jamf parameters.

**Steps:**
1. Find line ~439 in the script: `if (( last > 11 )); then`
2. Change `last=11` to your desired limit (e.g., `last=20` for 17 apps)
3. Find line ~499: `"Only parameters 4-11 processed"`
4. Update the warning message to match your new limit
5. Pass additional parameters via Jamf Pro API or direct script execution

**Note:** Choose either hardcoded apps OR parameters, not both.

### Timeout Settings

**Use when:** You have slower Macs or slower network/storage.

Edit lines 129-130 in the script:

```bash
TIMEOUT_DEFAULT=30    # Maximum time for app search and user commands
TIMEOUT_SHORT=10      # Maximum time for Dock restart
```

Increase these values if you see timeout errors in your policy logs. Default values work for most environments.

## Requirements

- macOS 10.15 or later
- Jamf Pro environment
- No external dependencies required

## Files in This Repository

- `clean_dock_v6.4.sh` - Main production script
- `CHANGELOG_v6.4.md` - Version history and detailed changes
- `v6.4_DOCUMENTATION_IMPROVEMENTS.md` - Quick reference guide

## Troubleshooting

**Apps not appearing in Dock:**
- Verify bundle IDs are correct
- Check app is installed on target Mac
- Review policy logs for errors

**Timeout errors:**
- Increase timeout values in USER CONFIGURATION section
- Check network connectivity
- Verify Spotlight is functioning

## Author

Ellie Romero  
ellie@theecr.com

## Version

6.4-PRODUCTION (January 22, 2026)
