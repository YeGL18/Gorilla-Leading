> Background follow-up (2026-11-04): see [background-energy-audit.md](background-energy-audit.md). Confirmed background stops now use a 20 m distance filter; foreground and active floor capture remain unfiltered. The original v3 table below describes the earlier baseline.

# Energy Optimization, Round 3

This work is on `ours/next`, layered over existing uncommitted parking, visit,
map interaction and UI changes. Those changes are preserved. Nothing was
committed, pushed or installed on the physical phone as part of this round.

## Changes

| Area | Before | Now | Deliberately Preserved |
| --- | --- | --- | --- |
| Destination routes / ETA | GPS and capsule timer could create overlapping `MKDirections` requests | One pending request per destination, cached route shared by ETA, visible route, rerouting and destination-meter distance checks | Explicit navigation and rerouting can force a refresh; cached ETA continues interpolating from its actual source/time |
| Route refresh | Could retry every fix or timer tick | Normally 30 seconds; after moving 250 m, earliest 10 seconds; failed requests retry after 10 seconds | Switching destinations cancels old callbacks; unrelated explicit parking/meter route actions remain independent |
| Dark Knight map | Two live map views, one blurred below the other | One live map with noninteractive native backdrop blur; shape masks rebuilt only on size/radius changes | Rounded container, black outer fade, normal map interactions and camera cadence |
| Orb updates | Root views observed the animation clock every frame | Only the small animated surfaces observe it; visible consumers acquire/release the clock | Existing orb paths, glow, colors and selected frame cadence |
| Hidden work | Day/night entry timer or orb clock could remain active without a visible consumer | Clock stops after the last visible consumer disappears; day/night stops with its view or scene | Foreground restarts visible animations |
| Title sheen | Continued requesting frames throughout transparent pauses | Original 120 Hz schedule during the 5-second sweep; one wake at the end of each pause | Original seven-pause sequence and phase calculation; system can request lower cadence |
| Day/night data | Color and sun calculations ran on every display-link tick | Once per second, with identical-value publication suppressed | Orb movement is not reduced to 1 Hz; the five-second entrance animation remains animated at its original cadence |
| Sun-time requests | Each GPS fix could request again while loading or after failure | Pending callers share one fetch, successful daily/location cache remains, failure retries wait 60 seconds | Both ISO dates with and without fractional seconds now decode |
| AMap | Automatic silent route/navigation could run alongside Apple MapKit | Automatic silent navigation and its lane overlay disabled; late SDK route callbacks cannot restart it | Apple map, routes, ETA and navigation; SDK dependency retained for other existing code |
| Adaptive GPS trial | Always requested navigation accuracy | Only after 60 seconds of continuous, fresh, reliable fixes at <=1 km/h and within 15 m, with floor sampling inactive, request nearest-ten-meter accuracy | Moving, motion detection, weak/unknown GPS, active floor sampling, fix gaps and foreground return retain/restore navigation accuracy; no distance filter or visit-monitor shutdown |

The native edge material is not mathematically identical to the old duplicated
map's Gaussian blur. It keeps a soft, dark edge but needs a visual comparison on
the physical phone. A native blur still has a GPU cost; removing a second map
does not remove all rendering cost.

## Verification

- `Tests/EnergyPolicyChecks.rb`: extracts the actual route/location policies;
  checks refresh intervals, failed requests, movement, GPS drift, fix gaps,
  stale/weak fixes, and floor sampling.
- `Tests/EnergyRuntimeProject.rb`: builds a disposable native test host under
  `/private/tmp`, without loading real parking/destination data.
- `Tests/EnergyRuntimeTests.swift`: request coalescing/cancellation, clock
  consumer lifetime, day/night publications, entrance cancellation, sheen
  scheduling, sun-time caching/parsing/backoff and map mask reuse.
- `Tests/EnergyVisualTests.swift`: screenshots the single-map edge effect,
  toggles it and checks native one-finger pan and two-finger zoom.
- Existing parking altitude, floor, entry-clock and visit-history tests are
  run to catch regressions in the unchanged parking behavior.

## Physical-Phone Checklist

- [ ] Switch between map, orbs and speed; every visible animation restarts.
- [ ] Background/foreground several times; no frozen orb or huge first-frame jump.
- [ ] Dark Knight map: inspect softened edges, compass and marker readability;
      pan, pinch and rotate normally.
- [ ] Set/change/clear destination; ETA updates, navigation draws the right route.
- [ ] While driving, check smooth tracking, rerouting and nearby/destination meter prompts.
- [ ] Short gate stops retain precision and continuous floor sampling.
- [ ] After a long stationary stop, start driving again; GPS and camera recover promptly.
- [ ] Compare a 60-minute drive on the same device, route, brightness, charging
      condition and ambient temperature. Record battery use and thermal state.

Simulator results validate behavior, not the amount of heat saved on an iPhone.
MapKit rendering, display brightness, GPS, network conditions and charging can
all contribute to heat. No measured percentage reduction is claimed here.

Final checks include stale route timestamps in destination-meter notices and
an independent saved-destination lookup that cannot cancel the selected route.

## Reversal Scope

Review this round's changes independently from the earlier uncommitted work.
In particular, do not restore all of `ContentView.swift`, `MapView.swift`,
`LocationManager.swift` or `ParkingMeterManager.swift` from Git: they also
contain earlier changes outside this optimization. The isolated areas above
and the new energy-test files identify this round's scope.
