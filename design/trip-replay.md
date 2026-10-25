# Foreground Trip Replay

Implemented 2026-10-23. Entry: Home, replay button immediately left of the GPS capsule. Recorded journeys can also
be opened from their linked visit-to-visit connector. No historic trajectory is
generated from old visit coordinates and no navigation route substitutes for GPS.

Replay transport uses separate floating Liquid Glass controls without an opaque
full-width bottom strip. Speed and altitude charts use monotone curves with a
subtle fill towards zero, preserving gaps and actual sample values. Acceleration
uses upward chevrons and braking uses the brake symbol, shared with Current Action.

## Recording

- Enabled by default following the user's explicit request for foreground trip
  recording; the library exposes a recording switch, retention and deletion.
- Only foreground, real GPS samples are admitted. Live AC reception and inactive
  scenes pause capture. No new background location permission, timer or service
  is introduced. Existing visit/parking behavior remains separate.
- A driving candidate requires two seconds at 5 km/h with automotive evidence,
  or 20 km/h without pedestrian evidence. Ten seconds of real pre-roll are kept.
  After starting, walking portions remain in the journey until arrival/end.
- A qualifying visit arrival ends the trip; the fallback ends a five-minute
  stationary tail at the last movement. Brief traffic stops remain in the trace.
  A manual finish is also available. These heuristics need real-world validation,
  especially congestion and delayed native visits.
- Samples are at most one per second during an active trip. Invalid coordinates,
  accuracy over 50 m, fixes older than ten seconds, out-of-order fixes and obvious
  one-fix teleports are excluded. Missing/invalid speed is nil, never a fake zero.
- Background, game and process restarts mark a break before the next sample.
  More than 30 minutes away completes the old trip. Links across more than twelve
  seconds, flagged breaks or implausible displacement are never drawn or counted.
- Origin/destination links use qualifying visits, time proximity and a 300 m
  endpoint check. They are associations, not inferred missing route geometry.
- Endpoint display names can match named parking facilities, saved destinations
  and learned places, in that order, within bounded local radii. Unknown points
  retain visit names; a nearby place never supplies missing route geometry.
- New trips can retain an actual departure-time prediction. The habitual-route
  suffix requires a completed trip, a prediction within ten minutes of departure,
  and a final position within 180 m of the predicted destination. Old trips with
  no prediction metadata are not retrospectively labelled. The optional archive
  field remains compatible with older histories and backups.

## Altitude

GPS altitude uses CLLocation.altitude, accepting finite -500...10000 m values
only with verticalAccuracy in 0...20 m. Negative sea-level elevations are valid.
It is not the parking-floor relative barometer measurement. A three-sample median,
two-second time-based smoothing and jump check suppress isolated spikes. Missing
or unreliable heights reset the altitude filter and create chart gaps, even if
the horizontal route remains available. This adds latency and is an estimate,
not a surveyed maximum. Highest/lowest altitude use the accepted smoothed samples.

Apple references:
- https://developer.apple.com/documentation/corelocation/cllocation/altitude
- https://developer.apple.com/documentation/corelocation/cllocation/verticalaccuracy

## Events And Playback

The speed page and recorder share the existing vibration-filtered motion source
with separate consumer leases; opening settings or leaving the speed page cannot
stop capture for the recorder. Sensor capture stops when neither needs it.
Events use SpeedActionTracker and are persisted only for a moving, non-pedestrian
real trip. Candidate/invalid/gap samples are not scored. Motion timestamps are
converted from uptime to wall-clock dates, and completed events wait for a GPS
fix covering their end. Phone orientation changes reset the shared filter.

The calendar lists trips by departure day, including ongoing records. A full map
and native resizable sheet present statistics, a selectable speed timeline,
selected-moment data, an altitude chart and compact event rail. Playback, scrubbing and
previous/next event selection move the map cursor. Gaps hide the cursor rather
than interpolating an unobserved route. Playback pauses offscreen/inactive.

Distance sums valid connected GPS links, excluding known stationary wander;
average speed is time-weighted over valid paired speed samples. Observed time
excludes gaps, total duration includes them, driving time uses recorded transport
evidence, and top speed uses valid samples. Speeds respect km/h/mph preferences;
distance and altitude remain km/m. Missing values show dashes, not invented data.
Charts use native Swift Charts with separate series for data gaps.
Both metrics use monotone curves and translucent fills down to zero, with subtle
axes and elapsed-time labels. Playback is an overlay of separate liquid-glass
buttons and a tick-mark time capsule, not an inset bar. Scroll-content bottom
margins keep the final rows reachable above it. The scrubber supports touch and
VoiceOver adjustment. Acceleration uses upright double chevrons; braking uses
the brake symbol, shared with the live current-action card.
Statistics initially show distance, average speed, top speed and duration; the
remaining six expand in place. Event count sits left of lowest altitude. Metric
groups use translucent solid rounded surfaces, not additional blurred materials.
The timeline title shows the event at the selected moment instead of a long list.
The MapKit replay map caches its route overlays and uses native marker views,
updating only the cursor while scrubbing. The theme-colored route has a white
outline at 55% opacity, narrowed to a 7-point outline around a 5-point line.
Route and marker colors stay blue/green in both appearances, independently of
the white dark-mode control tint. A scope button at the sheet's upper-right corner
keeps the sheet open and uses MapKit's animated camera fitting to frame all route
segments above the sheet. Changing a detent alone does not reset the map camera.
The map extends behind the status area. Its system navigation bar is hidden
entirely; back and details actions are independent circular glass buttons in a
safe-area-aligned map overlay, so no shared bar or horizontal edge blur remains.
The controls reserve a transparent top safe-area inset with explicit circular
hit areas, matching 20-point top/side margins and 8 points below the controls.
Library navigation uses a selected-trip binding, allowing the floating
back action to clear the destination and dismiss details together.
The destination title and origin-to-destination text live beside the sheet date;
the redundant sheet close button is removed. The overview glyph is enlarged inside
a standard 44-point circular button aligned with the top of the sheet header.
Back removes the sheet before initiating navigation rather than waiting for the
map's disappearance callback. The native sheet's glass backing and three height
stops are retained: the user's blur-removal request applies only to the shared
navigation region below the upper buttons, not to the details background.
The library uses its own fixed-height title/close/settings/menu row with native
Liquid Glass controls. Both library and map keep the system navigation bar hidden
throughout push/pop, avoiding the native bar's vertical collapse/expansion during
the horizontal transition. The header travels with its library page, not with
the system navigation-bar transition. Home passes an explicit library-close action.
The header reserves 20 points above its 44-point controls and 8 points below,
restoring the lower resting position without reintroducing bar visibility changes.
Calendar swipe deletion has an explicit red tint and trash label so the dark-mode
white navigation tint cannot turn its destructive action white.
Date selection fades the result rows including their solid grouped backgrounds
and separators, the section date and empty-history state:
an outer list mask begins just above the result header, measured in global
coordinates relative to the mask viewport. This includes UIKit's native grouped
backing; per-row SwiftUI opacity alone cannot fade that backing reliably. The
calendar region above the mask boundary remains opaque. A static grouped page
background behind the mask avoids flashing a different page color.
120 ms out, replace the displayed date without insertion/movement animations,
commit the new zero-opacity layout for 35 ms, then 180 ms in. This prevents newly
inserted rows from skipping their entrance or resizing an unfaded background.
Date-keyed tasks cancel outdated switches, and returning quickly
to the current displayed date restores opacity instead of leaving rows hidden.
The calendar itself remains visible throughout.
The timeline event badge uses an action-keyed opacity/scale spring transition,
including entering/leaving an event. Statistics expansion uses a damped spring;
the same chevron rotates and moves with the centered label instead of replacing
its symbol. Reduce Motion uses short non-spring fades/easing.
In dark appearance, playback/navigation controls
use white independently of glass preference; acceleration/braking labels and
event marks use orange. Metric surfaces use translucent gray at 12/16% opacity,
18-point continuous corners and an animated change between medium/large detents.
Playback controls sit another twelve points lower, with fixed 46-point buttons
and a shorter time capsule capped at 190 points, respecting the home indicator.

Playback and eased scrubbing use a display link requesting up to 120 Hz. The
native map cursor interpolates only between valid connected GPS fixes, including
longitude wrap; gaps remain hidden. SwiftUI charts publish the shared selection
at 60 Hz (30 Hz for over 2,000 samples) to limit redraw cost. Slow dragging tracks
closely; fast dragging adds a stronger short exponential lag and settles on release.
Speed, altitude and event curves remain in equatable cached chart views; only
lightweight canvas cursors observe changing playback time, avoiding full-series
layout/animation work on each scrub frame.
The detail root retains transport without subscribing to its frame publications.
Small time readers update only the current-event badge, selected moment and
playback controls; the entire native sheet and map wrapper no longer rebuild
at playback frequency. The replay cursor is a blue circular annotation with a
white rim and translucent halo, not a navigation arrow. Its screen position is
projected directly each display frame with implicit layer animation disabled.
This is a recorded position, never the device's live user location. Native
start/end markers remain unchanged. Refresh rates are requested, not guaranteed.
The full library row, including thumbnail, title and whitespace, is tappable.
Top speed and peak G use the current orb/dot palette with readable contrast;
highest/lowest altitude titles use green/blue, leaving other metrics neutral.
Readouts and glass transport controls now have a separate clock: up to 12 Hz
during playback and 30 Hz during scrubbing, instead of following every chart
publication. While the detail scroll view is tracking/decelerating, readouts
drop to 8 Hz, chart cursors to 15 Hz and readout transitions are disabled. The
map still receives every display-link frame and elapsed playback time is never
paused or resampled to achieve this. Curves, stored GPS samples and event timing
are unchanged.

The library and map share the same hidden navigation-bar state. Explicitly
restoring a visible bar on return was insufficient: final positions could match
while its title and buttons still jumped during the transition. Its grouped-section
fade boundary is held in a separate observable object
observed only by the mask, not by the whole List. Header geometry changes during
navigation no longer rebuild the library or apply a disable-animation transaction
to the list. The return test uses the same outer library sheet plus nested map
detail sheet as Home and checks calendar position before/after navigation.
Elapsed time uses numeric transitions. Reduce Motion bypasses scrub lag; actual
refresh rate remains subject to hardware, system scheduling and power settings.

## Storage And Privacy

Data remains in a protected, file-backed versioned archive in Application Support,
not a multi-megabyte preferences value. Serial utility queue writes occur every
thirty seconds and at journey start and lifecycle/end/delete boundaries;
the queue is drained before restore to prevent stale writes. Backups include the
archive (as a synthetic backup payload) and its preferences, with semantic validation before restoring. Corrupt
archives are preserved and recording is disabled rather than silently overwritten.
Legacy/early preference blobs are migrated only after a successful atomic file
write. Backup rollback and old-backup replacement also restore/remove the file.

Default retention is 30 days, selectable as 7/30/90 days. Additional safety caps
are 100 trips, 60,000 total points and 14,400 points/2,000 events per trip; oldest
completed trips are pruned at the cap. A four-hour sampled segment closes at its
point limit. Deleting replay data never deletes visits, parking memories or photos.

## Verification

Pure checks cover automatic start/end, pedestrian exclusion, weighted statistics,
GPS gaps/teleports, coordinate interpolation and longitude wrap, adaptive scrub
settling and frame-rate independence, quality gating, negative elevations, median spike rejection,
max/min altitude, visit linking, deletion, retention and archive validation.
The native UI harness uses production replay models, storage and views with an
isolated defaults suite and a motion stub. It covers foreground/game gating,
pause/resume gaps, persistence, deletion, corrupt archive preservation, calendar,
playback, charts and landscape layouts. Real GPS, altitude and in-car event
accuracy still require a foreground drive test on the iPhone.
The iPhone simulator's fifteen UI/store/policy tests passed on 2026-10-25,
including full-row title/thumbnail navigation, the recorded blue-dot annotation,
phone driving-state gating, long-parking history, label contrast and the haptic
preference, scoped dark/light VLM alerts, continued playback during scrolling,
as well as adaptive scrubbing,
returning while the detail sheet is open, both dark glass styles, half/expanded
sheets, dark-mode red swipe deletion, switching between populated and empty dates,
three-trip to one-trip to future-empty-day transitions, and landscape controls.
Simulator recording also checks intermediate fade frames rather than only settled
screenshots. The iPad test's assertions
passed, but its Xcode result-collection process stalled and was terminated;
that run is not counted as a fully completed iPad test session.
After isolating the list's fade-boundary updates, three focused return/date-fade
tests passed again, including the nested Home-style sheet. Return videos and
alert screenshots were inspected. The subsequent fixed-header revision keeps
the native navigation region hidden on both pages. Focused tests check title
and calendar positions, library settings, and three-trip/one-trip/empty-date
switching; transition videos supplement settled-frame assertions.
The current signed app was built, installed and launched on the user's iPhone
16 Pro without uninstalling or clearing its history. Simulator checks do not
guarantee a sustained 120 Hz on the device or verify real notification delivery,
physical haptic strength, GPS accuracy or long-term parking learning in traffic.
