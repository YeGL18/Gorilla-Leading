# Background energy audit — 2026-11-04

## What actually runs

| Work | Before this change | After this change |
| --- | --- | --- |
| Core Location | Standard location updates allowed in background, navigation accuracy, no distance filter, automatic pause disabled. Existing nearest-ten-metre reduction required 60 s of reliable stationary samples and no floor capture. | Movement and floor capture retain full precision. After a fully observed stable stop, background callbacks use a 20 m distance filter. Foreground return and walking/driving motion immediately restore unfiltered navigation precision. Sparse fixes after an already established stop do not reset the stationary policy. |
| Compass | Heading service remained subscribed off screen. | Stops on entering background, restarts in foreground. |
| Map heading | A 60 Hz repeating Timer could remain alive while Core Location kept the process executing. | Cancels itself off screen; driving display-link start/frame also reject background work. |
| Parking / stationary / departure display clocks | Separate one-second timers; parking timer also requested a WidgetKit timeline reload every second. | One visible elapsed-time clock, inactive in background. Times come from saved dates, not tick counts. Widget reload only on context/state changes such as starting parking. |
| Capsule status / ETA | Two-second timer continued checking state and could refresh ETA. | Background state checks use 30 s with 5 s tolerance. ETA polling and visual rotation are foreground-only. Native location/motion/visit callbacks are retained. |
| Live Activity | Repeated identical sync calls created ActivityKit update Tasks; periodic 60 s sync remained alive. | Identical snapshots are ignored; the periodic foreground sync stops in background. Native state/context changes can still sync. Timer rendering stays in WidgetKit. |
| Reverse geocoding | Once moved 50 m; only high-speed requests had a 5 s minimum interval. | Background address requests have a 60 s minimum interval. This does not throttle the separate CLVisit arrival/departure processing. |
| Parking floor altimeter | Automatic capture follows driving/location and continues in background; manual test capture is cancelled in background. | Preserved. Necessary to detect floor changes before parking; it can remain a significant sensor workload. |
| Motion activity | CMMotionActivity callbacks, history backfill (rate limited), visit/transport segmentation and car audio-route events. | Preserved. These are distinct from high-frequency G-force rendering. |
| Detailed replay / G-force | TripReplayStore already pauses detailed route/G-force capture in background. Speed page releases its motion consumers. | Preserved; do not describe detailed replay as recording continuously in background. |
| Game telemetry | Already disconnects when inactive. | Preserved. |
| Chat polling / scanner / traffic camera warnings | Existing foreground gating; parking reminders scheduled via local notifications. | Preserved. Local notifications do not need a one-second app timer. |

## Correctness and limits

- No location services, visit monitoring, automatic floor capture or motion activity permissions are removed.
- Automatic location pausing remains disabled for now: enabling it globally without an arrival/departure wake-up design risks missed departures/floor data. This first pass targets proven redundant work and confirmed stationary callbacks.
- GPS silence due to the intentional background stop filter is not interpreted as tunnel GPS loss. Foreground restores the original watchdog behaviour.
- Entering foreground rebuilds display timers from the original entry/departure dates. Manual departure and manual parking entry timestamps are not rewritten.
- The new configuration reduces requested work. It is **not** a measured percentage battery saving. Physical before/after energy traces are still needed under matching route, radio reception and screen conditions.
- Poor GPS and unknown speed retain high precision; an indoor weak-signal location may therefore still cost more energy than a footprint app that only uses CLVisit/significant-change services.

## Validation

- `ruby Tests/EnergyPolicyChecks.rb`: 85 checks, including short stops, GPS drift, sparse confirmed-stop updates, movement restoration, foreground and floor-capture sampling.
- `Tests/AirportDropOffChecks.swift`: separate parser/data checks for the new feature.
- Parking entry-clock, altitude and floor regression scripts, plus a device build.

Apple guidance: https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently

## Real-device follow-up

Compare locked-screen parked, walking, driving and parking-floor-approach periods. Check state changes/notification timing and location callback count as well as energy. Use Instruments/Power Profiler or Xcode energy diagnostics on a physical device; the system Battery percentage alone does not identify which subsystem caused the use.


## 2026-11-05 — complete background follow-up

- Live Activities no longer display or publish speed, route distance or ETA. They show state, the system-rendered anchored timer, and stable location/destination/parking details. Legacy optional fields still decode; telemetry-only changes are removed before comparing snapshots. Periodic ActivityKit sync is removed.
- Destination route requests are disabled and pending requests cancelled while the phone scene is inactive/background. Manual map directions share a cancellable owner and reject late replies. Existing selected destinations and displayed routes survive. Airport searches resume on foreground.
- GPS-loss checks and replay qualification timers use scene-scoped cancellable tasks. The remaining one-second departure clocks use the shared foreground-only elapsed clock. Parking notifications remain system scheduled; the foreground reminder checker stops off screen without cancelling delivery.
- Background visit status follows native location/motion/visit evidence, GPS updates coalesce to at most every 15 seconds, and finite state deadlines replace capsule polling. Old fixes cannot refresh the movement timestamp indefinitely.
- Current-address reverse geocoding and sunrise/sunset checks are foreground-only; native visit-address resolution is retained. Floor graph samples are only appended while visible.
- Reliable non-automotive stationary motion sustained for five minutes, with no floor capture, permits hundred-metre requested accuracy and a 50 m distance filter. A single deadline applies this even without fresh GPS. Moving/uncertain motion, reliable movement fixes, foreground or active floor capture restore/preserve precision. Standard location updates, CLVisit and motion monitoring are retained; this is not a complete GPS shutdown.
- Automatic floor sampling freezes a valid result after 90 seconds of stable stop plus non-automotive stationary evidence. Brief gates and automotive stops keep sampling. Unresolved automatic sessions time out at 15 minutes without inventing a floor; new driving evidence or manual sampling can restart capture. Manual capture remains user controlled.

Validation: 94 location/route policy checks, floor-capture and parking-entry-clock regressions, five native runtime checks for suspension/cancellation/foreground recovery/legacy Live Activity payloads, and light/dark simulator layout review of the production Live Activity components. A device build/install follows the final source changes.

No percentage battery saving is claimed. Compare locked-screen long-stop, walking, driving and parking-ramp sessions on the same physical phone; the test fixture validates UI and logic, not actual hardware energy use.
