# Gorilla Leading

**Remember where you parked. Understand the journey in between.**

A driving and parking companion for everyday journeys in Hong Kong: parking memory, nearby metered spaces, driving instruments, camera alerts and trip replay. A separate Android parking-community client connects to the same self-hosted service as iOS.

[繁體中文](README.md) · [Website](https://www.lucidtelos.com/apps/gorilla-leading/) · [TestFlight](https://testflight.apple.com/join/eFYTTma6) · [Support](https://www.lucidtelos.com/apps/gorilla-leading/help/)

## Project status

Gorilla Leading is in active development and testing. This README describes the current testing direction, not a guarantee that every feature exists in every branch or released build. `main` is the project overview; newer platform code is on [`codex/parking-community`](https://github.com/YeGL18/Gorilla-Leading/tree/codex/parking-community). Some recent changes may still be local and unpublished. Android is a parking-community trial, not a full iOS port. CarPlay integration requires Apple's entitlement approval.

## Highlights

- **Parking memory:** automatic and manual sessions, entry-time adjustment, photos, floor/area/bay details, reminders and editable map records. Non-driving stays are distinct from parking.
- **Editable places:** rename places, split grouped records, deliberately long-press to move markers, edit parking boundaries and drag polygon vertices.
- **Hong Kong parking meters:** nearby space information, occupancy where available, filters and route planning. Data freshness and actual availability can differ.
- **Driving instruments:** km/h or mph, G-force with a trail and temporary peak, acceleration/braking/turn events, and compact statistics and altitude/speed charts around the central speed display.
- **Trip replay:** recorded routes, a movable timeline, playback speeds, route overview or position following, driving events, speed/altitude curves and reorderable detail cards.
- **Traffic cameras:** nearby fixed speed/red-light markers, approach tones and configurable system speech. Road-reference speed limits can be matched from government data; unmatched values are a fallback, not verified camera limits.
- **Places and predictions:** visit history, learned places, saved destinations, habitual destination suggestions and MapKit route planning.
- **Assetto Corsa:** direct UDP telemetry from original Windows AC for speed, RPM, gear, throttle/brake and available session metadata. Game data remains separate from real GPS journeys.
- **Appearance:** orb, time-of-day, Dark Knight and M3 Concept themes; independent appearance/glass options; portrait, landscape, iPad and iPhone Duo layouts.
- **Parking community:** iOS/Android conversations, plate binding, reminders, replies, reporting/blocking and APNs/FCM integration with a configurable backend address.

## Availability and setup

The iOS deployment target is 26.0. Current development uses newer Apple SDKs for conditional features, including iPhone Duo. Direct Foundation Models image recognition requires iOS 27, a supported device and an available vision-capable system model; the shortcut option remains separate. Android requires Android 15/API 35 or newer.

See [feature details](docs/FEATURES.md), [development setup](docs/DEVELOPMENT.md), [security reporting](SECURITY.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

## Data and limitations

Location, motion, altitude, OCR and prediction results are estimates. GPS altitude is not parking-floor detection, and the driving score is not a certified safety assessment. Camera data does not cover mobile enforcement or guarantee current enforcement status. Follow road signs, traffic lights and the road itself. Configure the app while stationary.

Driving/parking features and the account-based community service have different data flows. See the [privacy policy](https://www.lucidtelos.com/apps/gorilla-leading/privacy/) and [terms](https://www.lucidtelos.com/apps/gorilla-leading/terms/).

## Source and licensing

Public visibility does not change the project's existing proprietary licensing position. No general open-source license is granted for the app source or brand assets. Third-party components remain governed by their respective licenses.

Built in Hong Kong. Support: [yeglyy18@gmail.com](mailto:yeglyy18@gmail.com).
