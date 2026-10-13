# Visit Recording and Transport Recovery

## Boundaries

- Native visit arrival/departure dates remain the source of time anchors.
- Parking memory, photos and arrival timers are immediate. Timeline minimum
  durations never delay or reset those sessions.
- Raw visit events and motion segments remain available. The formal timeline is
  a reversible projection, not destructive deletion of short visits.

## Timeline Preferences

- Completed new/active-place stays: minimum 10 minutes by default.
- Latest ongoing visit: visible immediately as a candidate below that minimum.
- Activate a new place after a 15-minute stay outside existing active areas.
- Match the nearest active place within 100 metres; default expiry is Never.
- Join consecutive same-place visits separated by at most 20 minutes. Preserve
  source IDs and raw dates; do not join across an intervening different visit.
- No manual split workflow. A-to-B duration uses departure A through arrival B.
- Active anchors are derived from retained visit history. Clearing that history
  removes those derived anchors; this is not an independent saved-place catalog.

## Transport Evidence

- Recover Core Motion history on startup, foreground return and native visits.
  The first query repairs a 2.5-day window, later queries overlap by five minutes.
- Discard low-confidence activity; preserve pedestrian/cycling evidence when
  activity flags overlap. Normalize overlapping intervals before classification.
- Stable non-driving segments of at least 60 seconds make a mixed trip.
- Pure driving requires recorded driving coverage of at least 85 percent. Missing
  history must not be inferred from current GPS speed, or stale saved motion.
- History recovery reclassifies automatic visits and matching map-point flags,
  preserving names, time anchors, floor fields and photo contributions.
- New manual transport edits are protected from automatic reclassification.
  Older manual edits did not store that marker and cannot be reliably identified.
- Relaunch restores the saved non-driving status, rather than forcing every
  active stay to parking. Explicit spot/area/floor contributions remain available.
- Presentation suppresses unknown/stationary/sub-minute transport fragments,
  while retaining the complete journey duration. Missing movement cannot be
  reconstructed if iOS no longer provides it or motion permission was denied.
- Driving activity alone cannot reliably distinguish private cars, buses and
  trains. No automatic public-transport claim is made from speed alone.

## Verification

- `ruby Tests/VisitHistoryChecks.rb`: production classification/timeline policy,
  36 minutes driving plus 14 minutes walking, delayed reclassification, actual
  point-flag batch update, manual edit preservation, timestamps and photo fields.
- `ruby Tests/VisitEventChecks.rb`: protected-data recovery, duplicate matching,
  arrival/departure ordering and long stays.
- `Tests/VisitSettingsUIProject.rb`: isolated production settings view with
  English/Traditional Chinese defaults, merge toggle and rotation screenshots.
- Full app Debug compilation. Sensor recovery still requires real-device
  validation; simulator fixtures do not demonstrate the user's actual history.
- No device installation or TestFlight upload is part of this change.
