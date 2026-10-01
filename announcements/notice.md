## Development Progress | v44

### SCRIPT 
- Fixed lineage override failure
- Bump system & vendor SECURITY PATCH to 05 OCTOBER 2026

### Boot Configuration (NEW WEB UI)
- Added Boot Configuration UI to fine-tune specific module settings and handle reboot-required configurations during fresh installation
[Click to see screenshots](https://t.me/MonaDump/336)

### Conflict Resolver (NEW WEB UI)
- Added conflict resolver to fix multiple root implementation
[Click to see screenshots](https://t.me/MonaDump/327?single)

### Keybox Source (NEW WEB UI)
- You'll be able to download keyboxes from other modules without installing them.
 [Click to see screenshots](https://t.me/MonaDump/322?single)

### Play Integrity WEB UI 
- Dropped Strong Mode 

### Boot Hash WEB UI 
- Improved UI
- Added Safe Mode lock
- Added reboot confirmation
- Added real-time status updates
- Added ability to auto get boot hash from TEEsim
[Click to see screenshots](https://t.me/MonaDump/334?single)

### Integrity Downloader WEB UI 
- Removed NoHello KPM - We don't need it anymore, syscall detection has been fixed in the latest version of folkpatch
- Removed Thor - HMA-OOS already spoofs installation source, so we don't need this anymore

### TRANSLATIONS
- Added a new “Become a translator” button to the Contributors section. It redirects directly to the translation template, making it easier for people to contribute translations and help make Integrity Box accessible worldwide.
[Click to see screenshots](https://t.me/MonaDump/332)
- Added Turkish translation by
- Added German & Romanian translation by [@Astegan](https://github.com/MeowDump/TRANSLATIONS/commit/e1bf92e4131f22f713eb7ec90a94bd80af459d06)
- Added Turkish translation by [@crackeren](https://github.com/MeowDump/TRANSLATIONS/commit/32d5f34fe9a4774013a8554632f6fb27e831fc4c)
