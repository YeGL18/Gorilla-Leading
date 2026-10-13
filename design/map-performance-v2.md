# Map performance pass 2

Based on `origin/ours/next` at `3c6c1a9`.

The map, route, marker labels, latest-point 30% enlargement, clustering,
tracking behavior and configured frame rates remain available. This pass removes
work when the underlying map data is unchanged.

- The main map passes `ParkingFloorStore.mapRevision` to annotation synchronization.
  Unrelated SwiftUI animation updates now perform an O(1) revision/selection check
  instead of hashing every parking record and floor string. Callers without a
  revision retain the content-hash fallback.
- Parking-range synchronization caches the store revision and selected point.
  It does not repeatedly search lots or hash boundary vertices on animation frames.
- Unchanged marker coordinates do not trigger coordinate KVO. Marker style setters
  and appearance snapshots are updated only when their displayed content changes.
- Parking boundaries keep their path throughout their fade; opacity changes do not
  rebuild or scale polygon/circle geometry. A shared, short-lived timer handles
  concurrent transitions and is invalidated when idle or when the map is dismantled.
- Meter polling only creates a refresh task when its configurable deadline is due.
  The request still rechecks concurrency/activity guards, and manual refresh still
  bypasses the interval. The default is 60 seconds; settings allow 30–300 seconds.
  Existing data-freshness checks remain in place.
- Stable-stop detection examines the recent eight-second tail rather than filtering
  the complete barometer history, preserving the same stability criteria.

Driving tracking now requests 120 Hz using CADisplayLink.preferredFrameRateRange;
drag timers retain their 60 Hz cadence, and parking-boundary opacity fades update
at 60 Hz. Disappearance-marker tracking retains its existing 120 Hz setting.
The app already enables CADisableMinimumFrameDurationOnPhone. Tracking smoothing
uses elapsed frame time and is checked at 30, 60 and 120 Hz; raising the callback
rate does not speed up motion or shorten fades. The requested refresh rate is an
iOS scheduling hint, not a measurement or guarantee of rendered FPS. No map
content or frame-rate option was removed.

## Interaction and floor changes

Released parking markers continue their existing exponential response until they
reach the final finger position. The drop coordinate is persisted once, after
settling. Cancellation commits the visible position without starting a glide.
Latest-marker scaling is applied to content, separately from MapKit's native view
transform; native selection inflation is suppressed while dragging.

Floor capture starts below 30 km/h. Stable, unattended captures are saved before
background suspension or when a matching automotive visit is bound. Those values
remain estimates, do not overwrite human-confirmed floors, and do not become
calibration evidence without human confirmation. No floor value is fabricated
when no usable capture exists. The locked-floor sound plays only on a manual tick,
not when parking is confirmed or when the picker times out.

## Validation

- Xcode simulator build of the application and widget targets.
- Existing parking-altitude and parking-level checks, including added checks for
  30 km/h boundaries, continued 25 km/h capture and unattended background storage.
- Camera-motion checks, including released-marker deceleration and frame-duration
  independence.
- Meter notice checks, including refresh defaults and preference changes.
- Native simulator gesture checks for pan, pinch, rotation, long holds, marker
  fade/reuse/anchoring, and stable scale under repeated native transform writes.

These checks validate behavior and removal of redundant work. They are not a
measurement of phone temperature or sustained GPU performance. A physical-device
comparison should use the same route, map style, frame-rate settings, brightness
and starting thermal state for both builds.
