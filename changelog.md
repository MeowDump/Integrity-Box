> Release Date: 22/08/2026

####  [🏆 Click here to support my work](https://meowdump.github.io/)

# What's New?

### Other
- Fixed bootloop on some devices
- Fixed issues related to fingerprint sensor on some stock ROMs
- Spoofed System & Vendor security patch to SEPTEMBER 2026

### Zygisk
- Synced shadow-hook integration from PIfork [#53](https://github.com/osm0sis/PlayIntegrityFork/commit/74118c33bab087dd434dbfee768daa80388d5d59)
- Bumped dependencies

### FP downloader
- Added flag support for Advanced, Strong, Match, Verbose, and JSON modes.
- Improved Android preview build detection with automatic Canary > Beta > Dev fallback.
- Improved Pixel preview device detection and selection.
- Added BusyBox fallbacks for `wget`, `date`, and `grep` compatibility.
- Added release-date detection and estimated expiry calculation.
- Improved migration to preserve existing PIF settings.
- Changed generated source configuration from `pif.txt` to `pif.prop`.
- Added optional JSON export to `/sdcard/meow.json`.
- Added automatic backup before replacing the existing configuration.
- Improved download, parsing, and missing-data error handling.
- Updated generated security patch to `2026-09-05`.

### Mirgrater
- Updated default security patch to `2026-09-05`.
- Updated default `DEVICE_INITIAL_SDK_INT` from `25` to `32`.
- Improved preservation of existing Advanced Settings.
- Improved handling of Pixelify, Legacy, Advanced, and Meta profiles.
- Dropped Google Wallet detection and `spoofProvider` logic.
- Improved configuration migration, backup, and cleanup.

### Installer

- Improved custom ROM detection using additional properties and package checks.
- Improved stock ROM detection for Samsung, Xiaomi, OnePlus/OPlus, and other devices.
- Improved sensitive-device and Safe Mode handling.
- Added automatic `disablegms` and `disablevending` flags for detected custom ROMs.
- Improved LineageOS property detection, sanitization, and Safe Mode cleanup.
- Improved build tag, fingerprint, `userdebug`, and `test-keys` sanitization.
- Improved VBMeta hash validation and configuration.
- Improved `resetprop` detection across different binary locations.
- Improved Zygiskless installation cleanup and removed obsolete PIF files.
- Improved module integrity checks, installer preparation, and migration handling.
- Moved ROM detection earlier in the installation process.
- Improved installation logging, recommended settings, and status messages.
- Updated Tricky Store security patch to `2026-09-05`.
- Removed obsolete `package.sh` service and duplicate installer logic.

### Bootloader Spoofer

- Redesigned the UI with a modern glassmorphism layout.
- Added app statistics for total, spoofed, and blacklisted apps.
- Added faster search with debounce, clear button shortcuts.
- Added --Spoof All-- and --Blacklist All-- bulk actions with confirmation.
- Added clearer targeted and blacklisted app states.
- Added loading skeletons, entrance animations, and improved mobile responsiveness.
- Replaced the old toggle with animated circular action buttons.
- Added About and confirmation modals.
- Added automatic removal of uninstalled apps from `target.txt`.
- Automatically sorts targeted apps to the top.
- Added TeeSim execution after target or blacklist changes.
- Improved backup/restore handling and UI performance.

### Prop Spoofer

- Redesigned the UI & added support for automatic property scanner.
- Added live scan progress, detection count, success, and error states.
- Replaced individual prop controls with five fix categories: Reset Props, Duck Props, PIF Props, Detection Props, and ROM Hide.
- Added automatic selection of detected properties for relevant fix categories.
- Added parallel execution for selected fixes.
- Added automatic re-scan after applying fixes.
- Added PIF conflict warning and detailed About/help information.
- Added execution timing and success feedback.
- Removed the old manual prop-selection, terminal, safe-mode, and per-property interfaces.
- Improved modal, toast, animation, and responsive UI behavior.

### Play Integrity Box

- Added configurable Advanced, Strong, Verbose, Skip JSON, and Skip Key controls.
- Added flag-based configuration for these controls.
- Added detailed information modal explaining each setting and its corresponding flag.
- Added automatic state refresh and protection against duplicate toggle actions.
- Improved Zygiskless and Advanced Mode compatibility handling.
- Improved automatic GMS restart after configuration changes.
- Added active/disabled states, animations, and improved UI layout.
- Improved warnings for incompatible configurations and missing Advanced Settings.

### Hide My Files

- Redesigned the UI with a modern glassmorphism layout.
- Added file statistics for detected, selected, and warning items.
- Added --Hide--, --Unhide--, bulk selection, Move, and Rename actions.
- Added animated progress, loading skeletons, empty states, and improved notifications.
- Added per-file Move-to-Vault and Rename/Mask modes with saved configuration.
- Added Vault structure, unhide tracking, collision protection, and operation logging.
- Improved handling for empty files, large files, and recovery paths.
- Improved responsiveness and overall interaction feedback.

### Control Center
- Added Safe Mode with automatic detection and protection against incompatible features.
- Added separate --Boot Flags-- and --Reboot Flags-- sections with risk indicators.
- Added automatic disabling and cleanup of incompatible flags in Safe Mode.
- Added flag verification after changes and improved action processing feedback.
- Added detailed information modal covering Boot, Reboot, Action, Kernel, and General settings.
- Added reboot hint when boot-related settings are changed.
- Redesigned the interface with grouped Settings-style sections.
- Improved modal, toast, animation, and mobile responsiveness.

### Advanced Mode

- Replaced Lite Mode with Safe Mode in Quick Settings.
- Added Safe Mode state detection, persistence, and compatibility protection.
- Added --Extract Boot.img--, outputs to `/sdcard/BootImages`.
- Added exit-code validation for script execution and Canary updates.
- Improved Update Canary status handling.
- Added dynamic Modern Mode background styling.
- Updated the help modal with the new settings and actions.
- Improved initialization and state handling.

