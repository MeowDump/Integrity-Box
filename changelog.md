> Release Date: 17/08/2026

####  [🏆 Click here to support my work](https://meowdump.github.io/)

# What's New?

- Added **WebUI translation support**.
   - 🇨🇳 Chinese translation by **@LQ2002**
   - 🇮🇳 🇵🇰 🇧🇩 🇦🇫 🇳🇵Hinglish translation by **Tehreem**
 
- Migrated to **resetprop-rs** with a complete backend refactor and various internal improvements.
   - Improved Hide Lineage
   - Improved Nuke Lineage
   - Improved Hide Custom ROM
   - Improved Hide PIF Detection
   - Improved Spoof Lineage Props
   - Improved Spoof Debug Fingerprint
   - Improved VB meta backend
   - Improved patch spoofing

- Added ability to **hide kernel-related detections**.
   - Spoof Build Time: Fixes duck detector system & kernel build date mismatch detection `(Tested & Working)`
   - Spoof Hide Custom Kernel: Fixes custom kernel detection `(NOT Tested & NOT Recommended)`
   - No Gore: Hides emojis & special characters from kernel string `(NOT Tested & NOT Recommended)`
   - Made in China: Hides stuff written in chinese language to avoid detection `(NOT Tested & NOT Recommended)`
   - No Telegram: Hides Telegram strings `(NOT Tested & NOT Recommended)`
   - No Mention Tags: Hides Mention strings `(NOT Tested & NOT Recommended)`
   - Spoof CMDline: spoofs CMDline `(NOT Tested & NOT Recommended)`
   - Spoof Kernel: Hides Kernel name strings `(NOT Tested & NOT Recommended)`
   - All of Above: Hides everything `(NOT Tested & NOT Recommended)`
 
- Synced with latest **PIF** source.

- Updated **system** and **vendor** security patch levels to **July 2026**.

- Improved **Keybox** script.

- Simplified and cleaned up scripts for better readability and maintenance.

- Changed Keybox backup source.

- Removed URL decoding.

- Removed force updater.

- Removed verification config updater.

- Cleaned up legacy code that is no longer used.

- Added a **Contributors** section to Support WebUI.

- Blacklisted selected browsers from accessing the Keybox, as they unnecessarily perform Play Integrity checks, which can ruin the Keybox.

- Updated Hashtag & URL in integrity downloader

- Updated HMA config

- Fixed known bugs
