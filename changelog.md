# Integrity-Box ( v5 )
> Release Date: 08/06/2025

# Important Note Before Flashing Integrity Box v5
CLEAN INSTALLATION IS MANDATORY

v5 comes with a lot of major changes, and to avoid conflicts with older versions of the Integrity Box module, It detects and removes all leftover files from previous installs that could interfere with the latest version.
Once detected, the script will clean up the old files and automatically reboot your device in 10 seconds. (to apply changes)

After reboot, simply flash the same v5 integrity box module again.

> What's new?
- Dropped openssl
- Dropped logkiller
- Dropped SusFS config updater
- Shipped with raven beta fingerprint
- Added Shamiko/NoHello auto whitelist enable/disable trigger
- Updated keybox
- Switched to silent fingerprint fetching
- Added assist status monitor in description
- Nuked scripts related to openssl & decryption
- Resolved compatibility issues with modules that rely on BusyBox
- Improved WebUI
- Fully compatible with MMRL
- Added Vietnamese translation (thanks to @Wuang26)
- Translated language switch tab
- Added installation fallback backup restore 
- Added curl + wget fallback if busybox fails
- Minor fixes & improvement under the hood

> NOTE:
If TrickyStore isn’t installed, keybox-related functions will be auto-skipped. All other features will still work.
Don’t need Strong Integrity? Just switch to AOSP keybox via Action / WebUI
