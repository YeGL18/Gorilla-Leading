# Marker, Time Phase, and Duo Follow-Up

## Native Home Map Handoff

The earlier shared-home layer outside TabView was reverted by the user because
it changed the native glass backdrop. It is not used in this version.

Home and the Duo Settings background retain their original native tab and
navigation hierarchies. Their UIKit hosts now share one MapPresentationContainer
and one MapView coordinator. Only the selected host may update or resize that
renderer. Switching hosts does not replay a tab-local camera trigger; removing
an old host cannot dismantle a renderer already claimed by the new host. A new
host with zero bounds does not temporarily collapse the live renderer.

When the last host is removed, driving/heading updates pause and callbacks
capturing ContentView are released. Reattachment restores the current parent
and tracking. Native glass styles, toolbar contents, button sizes, Settings
panel positioning, and user settings are unchanged by this handoff.

Tests/HomeMapSessionProject.rb generates a disposable project. The ownership
tests compile the actual session/host code against a small coordinator fixture;
the UI test launches the installed production app and compares renderer identity
across Settings round trips. Duo AX reports physical display bounds after
rotation, so the test uses the inner-landscape-only Gorilla tab as its layout
check. Device Hub was also inspected directly: Settings remains on the right
with the live map on the left. XCTest screenshot exports were black in this
environment; they are not evidence of glass appearance verification.

Final verification: six ownership/lifetime tests and the production UI test
passed on Duo iOS 27.1. Three Home/Settings round trips kept the same renderer
without replaying the entrance flight, and a one-finger drag after returning
to Home entered manual control. Drag coordinates are relative to the map
element, not the AX application's unrotated physical display frame.

## Scope

Keep the earlier energy changes and all pre-existing local edits. No parking
data, capsule position, map-follow camera, or saved settings are migrated here.

## Markers

- Separate MapKit's logical alpha from our short-lived appearance opacity.
- Re-delivered `didAdd` and reparent notifications do not restart a visible
  marker's entrance animation.
- Same-run-loop native layer hide/show flips are coalesced; only a hide that
  persists until the next run-loop turn triggers disappearance. Reuse generations
  cancel stale callbacks. Actual removals still fade immediately.
- Repeated selection requests do not restart the native selection animation.
- Disappearance snapshots retain their geographic anchor and actual opacity.
- Keep the existing native shape, drag handling, and latest-marker enlargement.

The exact phone-only shrink in the supplied screenshots was not reproduced by
ordinary coordinate/camera motion. The regression suite exercises opacity
read/modify/write, duplicate lifecycle callbacks, reuse, movement, and outgoing
world anchoring. Confirm the original long-press/move/hold sequence on the phone.

The follow-up on Duo iOS 27.1 adds actual single-finger pan/hold gestures with
both parking and meter markers. Movement pixel checks now render a map-space crop
to account for ancestor transforms, run during common run-loop modes, and exclude
unrelated map POIs in the fixture. Earlier apparent 70% area readings counted
nearby orange POIs in an oversized crop; isolated marker motion measured 98-100%,
and native pan measured 100% for both bodies. These simulator results do not
establish that the original phone-only disappearance has been reproduced or fixed.
No experimental rasterization, native-animation suppression, or additional scale
compensation was applied to production code.
All five marker regressions passed after visibility coalescing, including 100
transient hide/show pairs without restarting an appearance cycle, native pan,
coordinate/camera motion, cluster reuse, and outgoing world anchoring.

## Time-Based Orbs

The old dawn end could fall after the next phase's start. Treating any reversed
interval as a midnight interval allowed pre-dawn to consume daytime.

`TimePhaseSchedule` supplies the same ordered intervals to the live manager and
preview. Only night spans midnight. All seven existing palettes remain; night
starts at the actual sunset with a continuous transition over the preceding
30 minutes. The preview displays actual hours and minutes, including sunrise
and sunset. Positive hours are normalized without adding/subtracting 24, which
avoids floating-point shifts at exact minute boundaries.

Verification: 13 EnergyRuntimeTests passed on Duo iOS 27.1; the phase tests cover
every minute of three seasonal schedules, midnight, and the full sunset fade.
Four marker UI regressions passed on iPad iOS 26.1.
The same 13 runtime tests passed again on Duo during the follow-up.

The subsequent sun-data follow-up fixes previews created before the network
response: every manager observes the shared WeatherService result, using the
emitted value because `@Published` sends before its stored property changes.
The preview requests data for the current location and labels fallback times
explicitly. Requests specify the phone's local Gregorian date; successful
same-day/location caching and failure backoff are unchanged. The source remains
Sunrise-Sunset.org, not WeatherKit, with attribution in the preview.
The late-response regression failed before the fix and passed afterward.
All 15 runtime tests passed, including next-day refresh and all seasonal phases.
An actual API request for Hong Kong on 2026-10-10 returned sunrise 06:16 and
sunset 18:04 Hong Kong time; missing location/network still uses labeled defaults.

## Duo Navigation

- Inner portrait does not create a bottom compass toolbar or its backdrop.
- It uses the existing native 44-point compass view beside the header, 12 points
  below GPS, without another glass wrapper.
- Inner landscape and outer-screen poses retain their system toolbar compass.
- The TabView uses a dark glass environment; each page retains the selected
  appearance. Map, header, and capsule positioning are otherwise untouched.
- Native glass can still pick up colors from the map underneath. A fully
  controlled black tint or a decorative footer would require a custom bar.
  The native bottom accessory was tested and goes below the map, and the
  sidebar footer does not appear in the vertical tab bar. A real logo tab is
  supported without replacing the bar.
- The user subsequently confirmed that the logo should be a real fourth tab.
  Inner landscape now shows a 28-point Gorilla logo tab with an empty page.
  The logo tab icon shares the header's gold (#FFC46D), with pale diagonal
  highlights instead of a flat fill, in both glass styles, selected or
  unselected. Its original rendering mode prevents the shared bar tint from
  recoloring it. The standalone Settings icon keeps its previous template style.
  The subsequent softer version mixes the body 55% toward white at 75% opacity,
  and the highlights 80% toward white at 85% opacity. The header stays unchanged.
  Other forms retain three tabs; Settings has a standalone navigation link
  to the same page. Rotating out of the logo tab presents that page separately.
- Window measurement now responds to native layout and window changes, not
  only SwiftUI view updates. This keeps tab visibility current after folding.

Verification: both inner landscape directions show the fourth logo tab; inner
portrait and outer landscape show three tabs. The Settings link opens the
same page, and rotating while viewing the logo tab preserves it in a dismissible
presentation. Twelve layout-policy checks passed for Duo, phone, tablet,
split-window, square-window, and initial zero-size cases. Full Duo build passed.

## Dark Capsule Glass

The glass setting now covers address/GPS capsules, the native tab bar, and
the heading/search/map controls, including the Duo vertical toolbar. Dark mode
retains the tab bar's dark appearance and 0.55 black background with white items
at 1.0/0.7. Transparent mode removes that black background and forced dark style,
retaining the native default background effect without a black fill. The actual
on-screen tab bar is updated alongside the UIAppearance defaults, since changing
the appearance proxy alone does not refresh an existing bar. Both standard and
scroll-edge appearances are reset on a style change. UIKit's bar `backgroundEffect` only
accepts UIBlurEffect, not UIGlassEffect, so it is not assigned a custom glass
effect. The native bar compositor still controls its own glass rendering.

Address and GPS capsules use untinted native `.regular` in both modes, restoring
the original backdrop blur. Only dark mode forces a dark environment; transparent
mode follows the page appearance. Address corners remain 34 points; GPS corners
remain 22 points. Compact, expanded, parking memory, floor capture, and boundary
editing share the same address shell. Text follows the selected glass appearance; status colors, layout,
gestures, and transition timing remain unchanged. No extra blur layer is added.

The explicit capsule black tint has been removed rather than further reduced.
Both capsules now use the standard glass material, as
system glass controls do. The native tab bar keeps its system implementation;
its system compositor and the different backgrounds can still affect the final
appearance. No custom black fill or additional blur is introduced. The existing
Dark Knight address overlay is unchanged.

Settings > Appearance > Glass Style selects Clear or Dark Glass.
`capsuleDarkGlassEnabled` keeps its existing persisted key and defaults to true.
Transparent text follows the page's selected light/dark appearance. Custom map
buttons retain their original `.buttonStyle(.glass)` and 44-point image content;
the native style supplies the full control's padding and geometry. The appearance
modifier only changes foreground/color scheme: no fixed control frame, shape,
label style, or extra glass wrapper. Duo toolbar buttons and search retain their
system-managed backgrounds and sizing. Only the separate compass hides its shared
background, as before. Tab content is factored out solely to
keep the SwiftUI type-checker within its complexity limit.

Verification: full Duo build succeeded; two focused UI tests passed using the
production glass modifiers, settings picker, and UIKit bar appearance code.
They cover clear/dark switching, control state preservation, and persistence
after relaunch. Clear/dark screenshots were inspected. Clear glass still has
native refraction/highlights; it does not introduce a flat white fill.
An additional installed-app Duo test previously passed for the dark native toolbar
and search menu, including the existing overflow path when space is limited.
Those earlier tests did not validate preservation of original control geometry.
The subsequent forced 44-point circular control was incorrect and has been
removed. Tests now compare native control sizes before/after an appearance switch
instead of assuming a 44-point button. The control restoration was subsequently
built and installed on Duo after build approval became available.

The latest blur/tint follow-up passed both focused UI tests on Duo iOS 27.1.
The fixture reads the actual on-screen UITabBar standard/scroll-edge background
colors: dark has 0.55 custom alpha; transparent has no custom fill (nil or zero
alpha). It covers switching in both directions, unchanged control dimensions,
search interaction, and transparent preference after relaunch. Live appearance
updates are deduplicated per bar and configuration to avoid layout-driven writes.
The exported screenshots were all-black, so visual confirmation of the latest
backdrop blur remains pending despite successful UI interaction/state checks.

The native MKCompassButton now follows the same glass preference. Dark glass
overrides only the compass's interface style; transparent restores inherited
appearance. Both Duo toolbar/header compasses and the normal phone/tablet map
compass apply it on creation and update. No fill, blur wrapper, geometry, or map
appearance changes are added.

The focused native-compass UI test passed on Duo iOS 27.1: dark override and
inherited transparent appearance switch correctly in both directions, the native
compass bounds stay 44 by 44, and the dark preference survives relaunch. This is
the pre-existing compass size, not a new size for the map action buttons.

## Dark Knight Glass Override

Dark Knight temporarily forces the shared glass appearance to Dark Glass without
writing to `capsuleDarkGlassEnabled`. Capsules, map controls, native tab bar, and
native compass use the same effective preference. Turning Dark Knight off restores
the saved preference, including after an app relaunch. The settings picker shows
the effective dark appearance and is disabled during the override, preserving the
original preference. Manual and Focus-triggered Dark Knight share this policy.
No dimensions, positions, material parameters, or transition timing change.

Focused UI checks passed on Duo iOS 27.1 for restoring transparent glass after a
relaunch during Dark Knight, preserving an existing dark preference, disabling
the effective-style picker during the override, unchanged control sizes, and
native bar tint restoration. The native compass regression test also passed.
The first override test run tapped the switch row instead of its switch control;
the test now taps the trailing switch and waits for its actual value to change.
The complete GorillaTranslate workspace build also succeeded for Duo Simulator.

## Manual Checks

### Duo Inner Landscape Settings Follow-Up

Home and Settings previously each constructed their own `homeContent`, including
a separate native map. Inner landscape now keeps one shared Home layer across
these two selections. The native Home page reports its usable bounds so the map
retains its original viewport while Settings opens above it. The right-hand
panel retains the existing width, padding, corner, and animation parameters.
Other display forms retain their existing page routing.

The first background-layer prototype intercepted map gestures through the native
tab container and was rejected by the regression test. The final shared layer
is above that container, limited to the Home viewport, leaving native navigation
controls operable.

`Tests/DuoSettingsMapUIProject.rb` extracts the production shared container and
settings panel for a native-map fixture. The final Duo test passed for single-
finger panning, native toolbar actions, unchanged map dimensions/camera, and
four Home/Settings round trips with exactly one map creation. The workspace
build succeeded. A separate test against the installed real app also passed:
switching to Settings and back retains the ready map without another entrance
flight. Rotation/folding during an open Settings panel remains a manual check.

Run these installed-app checks only after building/installing the current app;
the fixture build does not itself rebuild GorillaTranslate.

1. Move/hold/release a parking marker and pan over individual and clustered
   meter markers. Their body size must stay constant while moving.
2. Scrub the orb preview through morning, afternoon, evening, and sunset. At
   sunset minus 30 minutes the fade begins; at sunset it reaches night.
3. Open the Duo inner portrait map, rotate to landscape and back several times.
   The portrait compass must stay below GPS, never in the horizontal tab bar.
4. Close the Duo and check both outer-screen orientations. The native vertical
   toolbar compass and map controls must still work.
5. Switch between Home, Speed, and Settings in light/dark appearance. Only the
   navigation glass should be forced dark; page appearance remains selected.

For rollback, revert only the follow-up hunks described here. These files also
contain earlier user/Claude changes, so do not restore entire files to HEAD.
