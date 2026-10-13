# Backup, Find-Car Card and Performance Checks

## Heat and Smoothness

Engineering owns instrumentation, simulator route checks and analysis. The driver
owns the final real-device test: a simulator cannot reproduce radio use, a hot car,
camera/GPS conditions, charging or physical thermal throttling.

1. In Settings > Data & Diagnostics > Performance Check, start recording before
   departure. Set a fixed brightness and note whether the phone is charging,
   its case and the starting battery level. Do not change settings while driving.
2. Use the map normally for 60 minutes. A passenger may note times of visible lag;
   otherwise stop safely before writing notes.
3. Stop recording and export the CSV. Compare the first 10 minutes with the last
   10 minutes: thermal state, CPU, memory growth and delayed callbacks.
4. Repeat on a comparable route, ambient temperature and charging setup before
   attributing differences to an app change.

Sampling is opt-in, every 10 seconds, stops after three elapsed hours and is not
saved across termination. It reuses existing orb/map-tracking display links. CPU
is process CPU summed across cores (can exceed 100%); memory is physical footprint.
Thermal state is iOS's classification, not a measured temperature in degrees.
Callback timing is NOT actual MapKit render FPS. No GPS trace or photo is recorded.
Background timer suspension is normal; this is a foreground usage test, not an
always-on background monitor. Instrumented timings still carry small overhead.

## Backup Coverage and Safety

Included: destinations and selection, visit/motion history, learned places and
patterns, parking lots/points/boundaries/floor learning, retained deleted records,
altitude results, parking entry adjustments/state, photo metadata and originals,
car Bluetooth selection, manual location corrections and user preferences.

Not included: iOS language override, permissions, credentials, downloaded meter
and weather caches, pending native location callbacks or old diagnostic reports.
The current photo feature stores at most three images; the backup covers all
currently retained images, not photographs already deleted by the existing app.

The versioned `.gorillabackup` is a binary property-list envelope with SHA-256
integrity checking, NOT encryption or proof of authenticity. Keep it private.
Only allowlisted app-owned keys and UUID `.jpg` names can be restored. Imports
are size limited (80 MiB) and validated before the user confirms replacement.

Restore replaces rather than merges. A safety snapshot is retained locally and
can be exported. A rollback journal is written before mutation; a failed or
interrupted restore rolls back before the app opens its stores. Language and
unrelated defaults are preserved. Old view timers are stopped and singleton
stores/photo caches are reloaded before a new ContentView opens. Live Activities
are ended and resynchronised with the restored session; widget timelines reload.

- [ ] Export a backup to Files and verify its date/count preview on import.
- [ ] Cancel the confirmation: records, photos and settings remain unchanged.
- [ ] Restore a known backup in a TEST installation; verify destinations,
      visit times, floor names, polygon boundaries and current photos.
- [ ] Verify manually adjusted parking entry time after restore and relaunch,
      including Lock Screen/Live Activity.
- [ ] Change app language, restore: iOS-selected language stays unchanged.
- [ ] Export the safety copy and verify it contains the pre-restore records.
- [ ] Invalid/truncated/newer-format files fail without applying any data.

`Tests/BackupChecks.swift` uses isolated preference domains and temporary files,
not user records. It checks round trips, replacement, rollback after file-write
failure, crash-journal recovery, photo bytes and language/key preservation.

## Verified in Development

The normal iPhone Duo workspace build succeeded. Four iOS tests passed for JPEG
and model validation, card rendering/metadata privacy, opt-in callback diagnostics
with numeric CSV columns, and replacement/rollback/crash recovery in disposable
preference domains. The standalone backup checks also passed. The rendered card
was visually inspected with a long bilingual place name.

These checks do not replace the manual Files picker/share-sheet checks below,
real-device Live Activity verification after restore or the 60-minute heat test.
No restore was performed against the user's actual app data.

## Find-Car Card

Share from the current parking-memory header. The snapshot uses that parking
session's point, not the user's current walking location. Original photos are
downsampled off the main thread for preview; only newly rendered card pixels are
shared (no source EXIF). Exact coordinates/Apple Maps link are opt-in. No new
network map request is made. Missing photos are not fabricated.

- [ ] Preview place, floor, spot, area and manually adjusted entry time.
- [ ] Toggle photos and exact location; preview matches the shared card.
- [ ] Share through the native sheet on iPhone/Duo/iPad; cancelling sends nothing.
- [ ] Long Chinese/Japanese place and spot labels wrap without clipped text.
- [ ] Current card never uses a historical parking point's unrelated photo.
