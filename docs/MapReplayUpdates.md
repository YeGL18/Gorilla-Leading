# Map and replay updates

- Normal home-map traffic camera markers now use a 1 km radius. The all-Hong-Kong camera browsing mode and 8-second approach alerts retain their separate behavior.
- The home GPS capsule uses sequential single taps: the first reveals and pins Map Details, the next opens browsing (or exits an active browsing mode). Automatic rotation cannot interrupt the pending second tap.
- The point rename dialog remains a native UIAlertController, with a system-blue confirmation action and destructive-red cancellation. Empty place names remain disabled; clearing an optional floor name remains supported.
- Active routes finish after fresh, reasonably accurate fixes remain within 45 m of the route endpoint at no more than 8 km/h for four seconds. Pending rerouting responses cannot turn a finished route back on.
- Replay overview and following are separate controls. Overview fits the whole route; following uses a closer camera and tracks the interpolated replay dot in the area above the sheet. Manual map gestures stop following.
- Linked visit display names take priority over nearby-place fallback names. The visit connector chooses a replay inside the actual departure-to-arrival window, including its midpoint, rather than accepting stale visit IDs on the next journey.
- The speed page uses a fixed, non-scrolling dashboard. Ten small statistics, compact current-action/G-force panels and small speed/altitude charts surround the unchanged central speed display. Portrait and landscape use different arrangements. There is no separate Trip Data page, history slider or selected-time cursor. A transient session starts only while the app reports driving; ending driving clears its points, events and totals without deleting replay history. It reuses the existing GPS feed.
- Replay following has a slightly higher speed-dependent camera distance (540–1100 m). The red library swipe action leaves the row in place until the confirmation dialog's destructive action deletes it.
- Completing or dismissing floor detection no longer automatically expands Parking Memory.
- Replay following uses an independent display clock, gradual road-direction turns and speed-dependent zoom. Normal motion tracks the already-interpolated point directly, without additional position lag. Screen projection anchors the point near the center of the visible area above the sheet. Large seeks remain damped; manual map gestures stop following and a settled camera stops its display clock. The map compass is hidden.
- The four replay detail cards support native long-press dragging. Their order is stored in the shared `replayDetailSectionOrder` preference and applies across journeys and app launches.

Validation includes the camera policy suite, replay recorder/name/window regression tests, a full app build, and UI fixtures for native rename, overview/follow separation and the data panel. Real-world arrival detection still depends on GPS quality.
