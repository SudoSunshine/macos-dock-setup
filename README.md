# macOS Dock Management Script for Jamf Pro

Enterprise-grade macOS Dock management script for Jamf Pro environments.

## Overview

This script clears the macOS Dock and adds specified applications using bundle identifiers. It's designed for enterprise deployment via Jamf Pro and handles edge cases like symlinked apps, Self Service version variations, and fresh Mac enrollments without Command Line Developer Tools.

## Features

- **Zero External Dependencies** - Pure bash using native macOS commands only
- **Fresh Mac Support** - Works on new enrollments without Command Line Tools
- **Smart App Discovery** - Double-fallback system (mdfind + find)
- **Automatic Fallbacks** - Self Service+ to classic Self Service detection
- **Symlink Resolution** - Prevents alias arrows in Dock
- **Path Normalization** - Clean, professional Dock entries
- **ShellCheck Compliant** - Production-ready code quality
- **Comprehensive Logging** - Detailed execution tracking
- **Lock File Protection** - Prevents concurrent execution
- **Timeout Protection** - Safe operation with automatic recovery

## Use Cases

- Standardize Dock across departments or roles
- New Mac onboarding and setup automation
- User migration or computer refresh workflows
- Self-Service Dock reset policies

## Version

**Current Version:** 6.4-PRODUCTION  
**Last Updated:** January 22, 2026  
**Author:** Ellie Romero (ellie.romero@jamf.com)

## Quick Start

### 1. Upload to Jamf Pro

1. Navigate to **Settings → Scripts** in Jamf Pro
2. Click **New**
3. Name: "Dock - Arrange Apps (V6.4)"
4. Upload `clean_dock_v6.4.sh`
5. Save

### 2. Configure Policy

1. Create or edit a policy
2. Add the script to the policy
3. Configure parameters 4-11 with bundle IDs:
   - Parameter 4: `com.jamf.selfserviceplus`
   - Parameter 5: `com.apple.Safari`
   - Parameter 6: `com.apple.Terminal`
   - Parameter 7: `com.apple.mail`
   - Parameters 8-11: Additional apps as needed

### 3. Deploy

1. Scope to target computers or groups
2. Set execution frequency
3. Deploy and monitor logs

## Configuration

### Standard Configuration (8 Apps)

The script supports up to 8 apps via Jamf Pro parameters 4-11:

```
Parameter 4:  com.jamf.selfserviceplus
Parameter 5:  com.apple.Safari
Parameter 6:  com.apple.Terminal
Parameter 7:  com.apple.mail
Parameter 8:  com.microsoft.teams2
Parameter 9:  com.tinyspeck.slackmacgap
Parameter 10: com.google.Chrome
Parameter 11: com.microsoft.Outlook
```

### Finding Bundle IDs

```bash
# Method 1: Using osascript
osascript -e 'id of app "Safari"'

# Method 2: Using mdls
mdls -name kMDItemCFBundleIdentifier -r /Applications/Safari.app

# Method 3: Using PlistBuddy
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Applications/Safari.app/Contents/Info.plist
```

## Advanced Configuration

### Extending Beyond 8 Apps

The Jamf Pro GUI limits parameters to 11 (8 app slots). Power users can extend this:

**STEP 1: Increase Parameter Limit**
- Locate: Line ~452 (search for: `if (( last > 11 )); then`)
- Change: `last=11` to your desired limit
- Example: `last=20` allows 17 apps (parameters 4-20)

**STEP 2: Update Warning Message**
- Locate: Line ~512 (search for: `Only parameters 4-11`)
- Change: `4-11` to match your new limit
- Example: `Only parameters 4-20 processed; extras ignored`

**STEP 3: Pass Additional Parameters**
- Option A: Use Jamf Pro API to add parameters beyond 11
- Option B: Call script directly via policy with extra arguments
- Option C: Create custom policy with extended parameter support

**WARNING:** More than 10-12 apps can clutter the Dock and impact UX. Consider using multiple policies for different user roles instead.

## How It Works

### Execution Flow

1. **Validate Target User** - Determines console user and validates username
2. **Acquire Lock** - Prevents concurrent execution
3. **Clear Dock** - Removes all apps from persistent-apps array
4. **Process Bundle IDs** - Finds and adds apps for parameters 4-11
5. **Restart Dock** - Applies changes with timeout protection

### App Discovery

The script uses a double-fallback system:

```
1. mdfind (Spotlight search) - Fast, indexes entire system
   ↓ If not found
2. find (filesystem search) - Slower but comprehensive
   ↓ If not found
3. Automatic fallbacks (e.g., Self Service+ → classic Self Service)
   ↓ If not found
4. Warning logged, script continues
```

### Symlink Resolution

Modern macOS uses symlinks for some system apps (e.g., Safari):

```
/Applications/Safari.app (symlink)
  ↓ resolves to
/Applications/../System/Cryptexes/App/System/Applications/Safari.app
  ↓ normalized to
/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app
```

This prevents alias arrows in the Dock and ensures clean paths.

### Self Service Fallback

Automatically handles different Self Service versions:

```
Try: com.jamf.selfserviceplus
  ↓ If not found
Fallback: com.jamfsoftware.selfservice.mac
  ↓ Result
Single configuration works for all environments
```

## Code Structure

### Function Organization

```
Section 1: LOGGING FUNCTIONS
  1.1 err()           - Log error and exit
  1.2 log()           - Log info message
  1.3 warn()          - Log warning

Section 2: TIMEOUT FUNCTION
  2.1 run_with_timeout() - Execute with timeout

Section 3: FILE LOCKING FUNCTIONS
  3.1 acquire_lock()  - Atomic lock acquisition
  3.2 release_lock()  - Release lock

Section 4: USER MANAGEMENT FUNCTIONS
  4.1 run_as_user()   - Execute as target user

Section 5: VALIDATION FUNCTIONS
  5.1 validate_bundle_id() - Validate bundle ID format

Section 6: APP DISCOVERY FUNCTIONS
  6.1 find_app()      - Find app by bundle ID

Section 7: URL ENCODING FUNCTION
  7.1 url_encode()    - Pure bash URL encoding

Section 8: DOCK MANIPULATION FUNCTIONS
  8.1 clear_dock()    - Clear all apps from Dock
  8.2 add_to_dock()   - Add single app to Dock

Section 9: MAIN EXECUTION
  9.1 Validate target user
  9.2 Implement lock file protection
  9.3 Clear the Dock
  9.4 Process parameters and add apps
  9.5 Restart Dock
```

## Troubleshooting

### Common Issues

**Issue: "Bundle ID not found" warning**
- **Cause:** App not installed or incorrect bundle ID
- **Solution:** Verify app is installed and bundle ID is correct

**Issue: Alias arrow on app icon**
- **Cause:** Older script version without symlink resolution
- **Solution:** Update to v6.4 or later

**Issue: xcode-select prompts on fresh Macs**
- **Cause:** Using Python/Perl-based URL encoding
- **Solution:** v6.4 uses pure bash (no external dependencies)

**Issue: Script runs but Dock doesn't update**
- **Cause:** Running as root or wrong user
- **Solution:** Script automatically detects console user

**Issue: Apps added but in wrong order**
- **Cause:** Parameters processed in order 4-11
- **Solution:** Adjust parameter order in policy

### Log Analysis

```bash
# View Jamf policy logs
tail -f /var/log/jamf.log | grep clean_dock

# View system logs
log show --predicate 'process == "clean_dock"' --last 1h

# Check Dock preferences
defaults read com.apple.dock persistent-apps
```

## Requirements

- **macOS:** Catalina (10.15) or later
- **Jamf Pro:** Any version supporting script parameters
- **Privileges:** Script runs as root, executes Dock commands as user
- **Dependencies:** None (pure bash, native macOS commands only)

## What Gets Preserved

- ✅ Dock folders (Downloads, Documents, etc.)
- ✅ Dock position (left, bottom, right)
- ✅ Dock size and magnification settings
- ✅ Auto-hide settings
- ✅ Recent items in Dock folders
- ✅ All user preferences

## What Gets Changed

- ❌ Dock applications (cleared and replaced)
- ❌ Application order (determined by parameter order)

## Version History

### v6.4 (January 22, 2026)
- Enhanced script description with use cases
- Improved advanced extension instructions
- Function numbering verified (all proper)
- Path normalization added
- ShellCheck compliance (SC2155 fixed)
- Added author and contact information

### v6.3 (January 22, 2026)
- Symlink resolution (prevents alias arrows)
- Path normalization for clean Dock entries

### v6.2 (January 22, 2026)
- Pure bash URL encoding (no Python3/Perl)
- Automatic Self Service+ to classic fallback
- Works on fresh Mac enrollments
- Improved error messages

### v6.1 (January 6, 2026)
- Reorganized structure
- Variables at top
- Cleaner header

## Testing

### Pre-Deployment Testing

1. **Test on single Mac:**
   ```bash
   sudo /path/to/clean_dock_v6.4.sh "" "" "username" \
     "com.jamf.selfserviceplus" \
     "com.apple.Safari" \
     "com.apple.Terminal"
   ```

2. **Verify logs:**
   ```bash
   tail -f /var/log/jamf.log
   ```

3. **Check Dock:**
   - Open Dock preferences
   - Verify apps appear in correct order
   - Confirm no alias arrows on icons

### Production Validation

Tested on production Jamf-managed Mac (SassyAIR):
- ✅ Fresh Mac enrollment scenario
- ✅ Self Service+ detection
- ✅ Safari symlink resolution and normalization
- ✅ Clean paths (no .. components)
- ✅ Zero xcode-select prompts
- ✅ Exit code: 0

## Files in This Repository

- `clean_dock_v6.4.sh` - Production script (562 lines)
- `CHANGELOG_v6.4.md` - Complete version history and changes
- `v6.4_DOCUMENTATION_IMPROVEMENTS.md` - Documentation improvements guide
- `README.md` - This file

## Support

**Author:** Ellie Romero  
**Email:** ellie.romero@jamf.com  
**Organization:** Jamf  

For questions, issues, or feature requests, please contact the author or open an issue in this repository.

## License

This script is provided as-is for use in Jamf Pro environments. Feel free to modify and adapt for your organization's needs.

## Contributing

Contributions are welcome! Please:
1. Test thoroughly in your environment
2. Maintain ShellCheck compliance
3. Follow existing code style and numbering
4. Update documentation accordingly
5. Provide clear commit messages

## Acknowledgments

- Jamf community for feedback and testing
- ShellCheck for code quality validation
- macOS Dock manipulation techniques from Apple documentation

---

**Status:** Production Ready ✅  
**Last Updated:** January 22, 2026  
**Version:** 6.4-PRODUCTION
