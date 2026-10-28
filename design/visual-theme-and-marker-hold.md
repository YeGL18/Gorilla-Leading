# Visual Themes and Marker Hold

- Appearance now has one Visual Theme picker: Orbs, Timeline, Dark Knight, M3 Concept. Existing raw values remain unchanged; Timeline is 3. The legacy normal + time-based-orb preference resolves to Timeline. Selecting a theme synchronizes the legacy background and Dark Knight preferences for compatibility.
- The nested Background Effect picker is removed. Timeline retains its preview controls; Dark Knight hides orb controls; Orbs and M3 retain their own rendering and mixing controls.
- Stay memory temporarily disables parking-space recognition without changing the stored VLM preference. Photos are still saved. Recognition is guarded before clipboard access and before starting polling; changing into stay memory dismisses the prompt and cancels active polling, sound, and recognition animation.
- Home parking/stay markers require a 0.6-second hold. Content enlarges to 1.28 times its existing scale during that hold, without altering MapKit's view transform. Successful unlock and release provide haptics subject to the app preference. Early movement, release, or cancellation restores the scale. Global long-press feedback ignores maps so it cannot vibrate before the marker unlocks.
- Verification: standalone theme migration checks; focused simulator tests for theme selection/persistence, M3 controls, marker hold/early movement, and marker scaling; final device build and installation.

This change does not upload another TestFlight build. Build 1.0 (5) already uploaded to TestFlight remains unchanged.

## Follow-up: Stable Drag and Recent G-force Peak

### Superseding Marker Rendering Fix

The captured-marker approach below failed on a physical iPhone: its raster image could be clipped and selected native marker scaling was still unstable. It has been removed from the home map. Parking and stay points now use `ParkingRecordMarkerView`, a fixed-bounds `MKAnnotationView` with a vector pin, glyph and separate text labels. Hold enlargement only transforms the pin content around its bottom anchor, never the map-owned view or its frame. The same live marker remains visible throughout dragging; there is no screenshot replacement or delayed rendering handoff. Unchanged configuration no longer resets a running hold animation. Native selection does not resize this custom annotation. Existing legacy native-marker classes remain for other marker/testing paths.

- Lock native marker selection at touch-down, not only when the 0.6-second hold completes. Only the dedicated short-tap handler restores selection. Delayed selection after dropping remains blocked until a new touch.
- During coordinate updates, display a noninteractive captured marker above the map, with fixed bounds and only its center changing. Suppress the native marker's drawing during that interaction. Release shrinks the preview, then hands drawing back after position settling; starting another hold cancels and completes any pending handoff first.
- The G-force card shows the current magnitude and a separate recent peak. It consumes the existing vibration-filtered phone readings (or AC telemetry). Forces below 0.04G for ten continuous seconds clear the peak; shorter pauses and changes of turning direction preserve it. Invalid/stale data, leaving the active scene, and switching data sources reset this temporary tracker. Trip replay's recorded peak is unchanged.
- Simulator marker tests passed: hold gating, scale/selection regression checks, and coordinate/camera motion pixel checks (minimum visible area ratio 100% of baseline in the test). Standalone force tests cover short pauses, a renewed higher peak, ten-second reset, gaps, invalid data, and filtered 0.12G engine vibration.
- The G-force card UI test also passed: a 0.50G peak survives a drop to 0.20G, then clears after ten seconds of 0.01G quiet readings. The final physical-device build succeeded. The first installation attempt found the iPhone unavailable; after the owner restored Wi-Fi connectivity, installation and launch on the iPhone 16 Pro both succeeded on 2026-10-26, preserving existing app data.
