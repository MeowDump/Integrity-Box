# AutoPilot v2

ARM64 Android engine with POSIX entry points. Build with `./build.sh` from this directory on a clean, committed tree (it runs the full test suite and writes the binary and its provenance into `../webroot/common_scripts/bin`) (Go 1.24+, validated with Go 1.27.2). No third-party Go dependencies. Binary uses Android's native curl for netd/bionic DNS; HTTPS verification remains enabled. Google attestation trust anchors are embedded from https://android.googleapis.com/attestation/root (retrieved 2026-11-07); public-key pinning permits equivalent reissued roots. Root changes require a reviewed rebuild.

`webroot/common_scripts/autopilot.sh` commands:

- `status`: JSON with desired enablement, verified daemon lock ownership, current local certificate health, revocation freshness and next deadline. Integrity verdict is explicitly not measured by this engine.
- `enable`: persist enable flag and detach one supervised daemon. First ordinary check is due after approximately two minutes, subject to screen/charging/battery/temperature gates.
- `disable`: remove enable flag, signal verified supervisor identity and wait up to 35 seconds for cancellation/transaction completion. Failure is reported rather than claiming stopped.
- `start`: idempotent detached service start if enabled, used by boot.
- `probe`: bounded network search and validation without installation. Diagnostic status and locks live in a separate RAM subdirectory.
- `run-once`: explicit manual update via normal priority cascade; not used to trigger the final natural recovery experiment.
- `import PATH [1|2|3]`: validate and transactionally import exactly the requested file; no fallback to unrelated sources.

Official `key.sh` and `spectre.sh` entry points delegate to the same engine. All automatic requests share one RAM search lock. All installations share one RAM write lock. Disabled autoservice does not prevent an explicitly requested manual import/update.

Source order: skip-default enabled -> secondary, Megatron, emergency Megatron2; otherwise Megatron, secondary, Megatron2. The emergency tier is attempted only if the existing certificate is unusable/revoked. A valid existing certificate is preserved on transport errors or inferior replacement. Names/expiry never imply two integrity verdicts. Any rejected/unchanged secondary candidate advances to the next bounded candidate rather than aborting the source.

Limits: one search deadline 90 seconds, secondary 45 seconds, each HTTP operation 10 seconds (connect 4), up to five unique secondary payloads plus one attempt per official tier. HTTPS host/redirect allowlist, maximum five redirect hops. Catalog/payload/XML limit 1 MiB; revocation response 4 MiB (live response around 181 KiB). Runtime Go memory target 32 MiB is a soft GC target, not a hard RSS limit. No global DNS, SELinux policy, wakelock, reboot, keystore kill or system power-profile changes.

Retries: 30 minutes, two hours, six hours, then up to twelve hours indefinitely, with jitter. Retry-After cooldown is per host, bounded to 30 minutes–24 hours. Charger reconnect can accelerate due work only after a 30-minute attempt cooldown. CRL has its own freshness window (Cache-Control clamped to 30 minutes–12 hours); ETag/Last-Modified conditional requests supported. CRL failure is unknown/stale, never a successful verdict. Cached evidence and search cursor are RAM-only and reset after reboot.

The scheduler uses /proc/uptime for suspend-aware deadlines. No alarm wakes a suspended phone: work is postponed until an ordinary eligible wake. On battery, screen off or low battery defers work; external supply is detected through usb/pc_port/dc online, including Not charging at a charge limit. A 25-second grace is measured after the screen is observed on; polling may delay work further. Two lightweight service loops poll at most once a minute in steady state. Supervisor doesn't use stale heartbeat to kill a suspended child.

Installation: parse XML/DER, validate private/public pairing, chain signatures, supplied trusted root and dates. File write transaction is staged on each target filesystem, preserves existing ownership/mode/context, journals bounded original copies, renames and syncs directories, and verifies bytes. Copies of the previous content exist only inside the transaction journal and are removed when it completes: no backup of a key stays on the device. Recovery rolls unfinished transactions back and removes a stale `keybox.autopilot-backup.xml` left by older versions. Main and enabled TEE-SIM/OMK consumers are prepared together; multiple paths cannot have a globally atomic rename. The journal handles interruption, but cannot make external consumers observe a simultaneous multi-file change. Tricky Store documents immediate config reload; no unconditional keystore restart is used. Other consumer-specific reload behavior remains a runtime compatibility concern.

Tests: host race detector, vet, POSIX ShellCheck, a WebUI behaviour test (`test_webui.cjs` runs the page's functions in a Node `vm`); the Go test binary also runs under Android root in a private RAM directory. Android-only tests exercise SELinux labels, actual same-filesystem commits and journal recovery using synthetic fixtures, never the working keybox.

Known verification limits: unit tests/fault scenarios are not certification of every ROM, actual power loss, all optional consumers or 48-hour battery behavior. Service acceptance does not guarantee Play Integrity acceptance. Real verdicts require the checker application and an unlocked UI. Legacy action.sh retains its unrelated broader operations; AutoPilot never invokes that action.

## Completion hardening (2026-11-07)

The updater now restores pending transactions before the framework/power gate,
preflights all backup files, and uses v1 checksummed journals (v0 recovery retained
for migration). Slots 1–3 share the recovery allowlist. CRL-only checks preserve the
independent replacement deadline and failure count; a new revocation identity can
accelerate one search subject to the 30-minute minimum and host rate limits.

Before writes, Android14 `cmd time_detector get_network_time` is checked with a
4-second bound, sample age at most24h, uncertainty at most60s and current-clock
agreement within5min. `/proc/uptime` precision is accounted for. Unsupported/stale
responses block automatic/manual updates rather than assuming correctness. This
is a platform-specific time-evidence adapter, not a guarantee for other ROMs.
`clock-status` exposes its current result without changing the keybox.

`fetch TIER` installs from one named official tier (for example `Megatron2`). `pif-refresh` runs one fingerprint-contour cycle on demand and waits for a running daemon cycle (exit 4: busy or interrupted).

`configure FLAG on|off` controls autopilot/disable-default-source/omk-key/sim-key.
It serializes mutations and increments a persistent revision on actual changes;
install takes writer then config lock, config mutations take only config lock.
External legacy touch/rm cannot provide the same ABA guarantee and should migrate
to this entry point. Imports now require a fresh CRL. UI shows their failure text.

New status fields include ready, time_state, next_search_due, next_crl_due and
installed_source. Installed source is unknown when RAM provenance is missing;
`source` remains the last attempted tier. Emergency Megatron2 fingerprints are
recorded durably before installation, so restart does not stop upgrade attempts.
A verified non-anchor candidate may have shorter lifetime than the emergency
anchor. Pre-existing unclassified files are not declared anchors from dates or
Subject strings alone.

Worker stderr is bounded in RAM and classified; its raw text is not logged.
Exit codes and sanitized HTTP/telemetry failures go to logcat. No timing behavior
is claimed from process presence alone. `observe.py` optionally records bounded,
read-only hourly status/hash samples on the host; transport gaps are missing
evidence, and this sampling is not an A/B battery benchmark.

Final validation hardening rejects ambiguous XML scalar fields/namespaces and
non-CA signing certificates, and performs full X.509 path validation. The stable
identity of an emergency keybox is derived from leaf certificate DER, so XML
formatting cannot bypass anchor recognition; raw file hashes still protect CAS.
Revocation entries must have canonical certificate serials and known statuses;
a malformed response cannot erase previously known revocations. Runtime metadata
has explicit byte limits. A corrupt config revision blocks installation but does
not prevent stopping the service. Pilot displays verified process liveness rather
than interpreting an old heartbeat during suspend as a dead process.

## Consumer acceptance (2026-11-13)

`status` reports `consumer` (`id`, `required`, `present`, `state`, `evidence`, `checked`), `time_source` and `config_notes`.

- A keybox must fit the strict consumer profile (`EC PRIVATE KEY` / `RSA PRIVATE KEY`). A local file that does not is reported as `consumer_incompatible` and replaced; candidates that do not fit are skipped. Tricky Store 1.4.1 cannot load PKCS#8 (`PRIVATE KEY`) keys.
- After each install, when the file changes, and at most every `probe_interval_hours`, the engine asks the consumer to re-read the file (open for append and close, content unchanged) and reads its verdict from the log after a random marker. No marker means `unknown`: nothing is rolled back and nothing is reported as accepted.
- A confirmed refusal restores the previous valid key, remembers the refused fingerprint (`.autopilot-rejected.json`, 64 entries, oldest evicted) and tries the next candidate.
- If the required consumer is not installed, no search or install is attempted (`required_consumer_missing`).
- Revocation lookups match both hex and decimal serials (Google lists 64-bit serials in decimal). Automatic installs require a fresh revocation list.
- Catalog entries that are expired or already listed by Google are not downloaded; longer-lived entries are tried first.
- Time evidence falls back to the `Date` header of a TLS-authenticated Google response when Android's network time is unavailable.

Limits: acceptance is inferred from the consumer's log, not from Google. Only a real Play Integrity check measures the verdict.

## Policy file: /data/adb/Box-Brain/autopilot.conf

Read at the start of every cycle; a change also wakes the daemon. `key = value`, `#` comments, at most 16 KiB and 200 lines. Out-of-range numbers are clamped and unsafe lines are skipped one by one and reported in `status.config_notes`; a file over the size or line limit is ignored and the defaults apply. The file cannot switch off HTTPS, chain verification or atomic installs.

| Key | Default | Bounds |
|---|---|---|
| `candidate_budget` | 5 | 1..10 candidates downloaded per search |
| `source_priority` | `TAKR,@Xiaomi_Lei_Jun,@Samsung_Jae_Yong,Yuri` | up to 16 names, unlisted sources last |
| `renew_before_hours` | 24 | 6..168 |
| `probe_interval_hours` | 6 | 1..48 |
| `probe_settle_seconds` | 5 | 1..15 |
| `extra_hosts` | none | up to 8 plain DNS names (HTTPS redirect hosts) |
| `pif_mode` | `auto` | `auto` repairs the patch pair and replaces a bad fingerprint, `manual` only reports, `off` disables the fingerprint contour |
| `pif_renew_before_hours` | `72` | 24..336: replace a fingerprint this long before it expires |
| `pif_lifetime_days` | `42` | 14..90: how long a Canary fingerprint is considered usable after its release date |
| `pif_probe_wait_seconds` | `15` | 5..30: how long to look for the spoof in the log after Play Services restarts |
| `pif_follow_latest` | `off` | `on` also replaces a still valid fingerprint when a newer build exists |
| `pif_sync_patch` | `on` | keep `security_patch.txt` equal to the fingerprint's `SECURITY_PATCH` |
| `pif_probe` | `on` | restart Play Services and check the log after an install |
| `pif_sources` | `archive,google` | fingerprint sources, in order |
| `consumer.tricky_store.modules` | `tricky_store` | module ids |
| `consumer.tricky_store.tag` | `TrickyStore` | log tag |
| `consumer.tricky_store.rejection` | `Load Keybox failed`, `valid keybox.xml was not present` | repeatable regular expression, up to 8 |

Example: if a Tricky Store update changes its log wording, add `consumer.tricky_store.rejection = new text` and no rebuild is needed.

## Doctor

Fingerprint search pace: a replacement is searched when the fingerprint is expiring, expired, banned or absent, normally every six hours (with growing pauses while sources are unreachable). While the installed fingerprint is banned and nothing eligible exists, the archive is polled hourly and the denylist is refreshed in the same pass; the Google source is asked at most once every six hours by one phone. `pif_follow_latest = on` keeps the newest Canary installed, so a ban of the old build finds the new one already in place.

`sh webroot/common_scripts/autopilot.sh doctor` is independent of the compiled engine (it works even when the binary is missing). It prints `OK/WARN/FAIL` lines for tools, consumer, key format, certificate count and validity (parsed from DER with `awk`), the acceptance probe and the engine status, never prints key material, and exits 1 on any FAIL. It reads the same `autopilot.conf` keys as the engine for what it checks (`renew_before_hours` and `probe_settle_seconds` with the same clamping, and `consumer.tricky_store.modules`, `.tag`, `.rejection` with the same validation). Host tests: `sh autopilot-v2/test_doctor.sh`.
