# First-Run Tour and Support Website

Updated: 2026-10-25

- Journey: a fixed Central road geometry checked against MapKit directions. A single distance/time model drives both the arrow and km/h display: acceleration is limited to 2.6 m/s², braking to 3.8 m/s², and cruise smoothly varies between 48 and 62 km/h rather than staying at the maximum. Corner limits are raised proportionally but remain lower than straight-road speeds. It starts from rest, decelerates before turns and remains stopped at the destination. No time compression or automatic teleport back to the start. A display link updates the marker without rebuilding SwiftUI; speed publishes only when the rounded value changes. Reduce Motion pauses the demo. It does not depend on a network directions request.
- Meters: real TD coordinates for Cotton Tree Drive, Central (poles 3186 and 3774). Colours are explicitly illustrative, not live occupancy. Source: https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv (2026-10-24 dataset).
- Parking: Stonecutters Bridge Viewpoint, fixed on-land location. No fictitious basement or changing floor. Status uses a compact glass capsule and a seconds-based timer.
- Privacy: Repulse Bay, explicitly labelled as a demo with a native beach place marker, not a fabricated user-location dot.
- Continue/Start: clear interactive Liquid Glass floating over the scroll viewport. Extra scroll-content spacing keeps the final text reachable, without a bottom safe-area material bar or clipped viewport.
- Viewpoint coordinates: OpenStreetMap contributors, node 1645491862, https://www.openstreetmap.org/node/1645491862 (ODbL). Map tiles and route directions: Apple Maps.
- The tour never writes visits, creates parking records, starts actual location services without the user's permission action, or alters onboarding completion when replayed from About.

## Support Website

Source: `sites/gorilla-leading`, a separate Sites-managed repository. Site identity is persisted in its `.openai/hosting.json`. Do not create a second site for updates.

- Home: https://gorilla-leading.divine-amber-0182.chatgpt.site/
- Help: https://gorilla-leading.divine-amber-0182.chatgpt.site/help/
- Privacy: https://gorilla-leading.divine-amber-0182.chatgpt.site/privacy/
- Terms: https://gorilla-leading.divine-amber-0182.chatgpt.site/terms/
- Support: yeglyy18@gmail.com (owner supplied and approved for public display).

The site is a static support centre: no added analytics, forms, account system or paid services. Hosting providers may still process operational logs. Policies describe the implemented local records, optional Shortcuts/VLM flow, Apple Maps, government meter data, sunrise-sunset.org and LAN telemetry. Review the policy whenever data handling changes.

Rating uses the owner's existing App Store ID, 6822058970, rather than the website. The public HK lookup returned no listing during verification, so the review destination cannot yet be verified end to end; it depends on App Store availability. App Store Connect metadata has not been changed.

## Verification

`ruby Tests/OnboardingUIProject.rb` produces an isolated test host using the production onboarding view. `Tests/OnboardingUITests.swift` walks all five pages and captures portrait and landscape states without touching real user data.
