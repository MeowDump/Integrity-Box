> Release Date: 07/07/2026

####  [🏆 Click here to support my work](https://meowdump.github.io/)

# What's New?

### Additional changes
- Added **Keybox Update** support for **Oh My KeyMint**
- Added **Scoop Update** support for **Oh My KeyMint**
- Added **Device Spoofing** support for **Oh My KeyMint**
- Spoofed to **July 2026 Android & Vendor Security Patch**
- Removed **MMRL** configuration
- Removed the red edge glow indicator from iframe gestures
- Fixed `resetprop` failures that occurred in certain Prop Spoofer scenarios
- Switched Prop Spoofer to use the compact `resetprop` implementation
- Added a brief warning note for users
- Improved the default settings and configuration

### Core Changes
- Switched configuration to prop format for better compatibility
- Synchronized with latest PIFork codebase
- Dropped per-app spoofing support 
- Brought back pixelify spoofing 
- Fixed battery drain issues caused by background processes
- Fixed RCS messaging issues on certain carriers
- Introduced **Repair Mode** click this when Play Integrity is failing or fails after some time or key attestation shows "bootloader unlocked" even with a valid keybox
- Added automatic cleanup of previous key database before Keybox updates
- Added GWallet and key attestation packages to default target scope
- Updated ZN hash/link reference to latest

### Removed Features
- Dropped Beast Mode
- Dropped Beast Mode WebUI
- Dropped Integrity Status WebUI
- Dropped per-app Device Spoofing WebUI
- Dropped Auto Pilot
- Dropped Auto Pilot backend
- Dropped Custom Fingerprint WebUI
- Dropped Flagged App Scanner UI
- Dropped Keybox Update WebUI
- Dropped Patch Spoofing WebUI
- Dropped Spoofed, Vending & Autopilot indicators from dashboard
- Dropped Daemon backend
- Dropped Local Fingerprints backend
- Dropped Integrity Box backup configuration
- Dropped unnecessary/redundant code throughout

### Dashboard Updates
- Added Play Integrity status directly to dashboard
- Removed legacy indicator icons (spoofed, vending, autopilot)

### Bug Fixes
- Fixed some apps crashing on some ROMs
- Fixed safe mode getting re-enabled on stock/spoofed ROM after module update even when user manually disabled it
- Fixed Keybox status not updating correctly in module description
- Fixed installation flow to use ASK checks when setting fingerprint

### Backend & Cleanup
- Cleaned up unused code and removed redundant logic
- General performance improvements and stability fixes
- Probably more that didn't make it into this list (i don't remember)
