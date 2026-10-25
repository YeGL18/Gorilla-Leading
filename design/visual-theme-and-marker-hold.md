# Visual Themes and Marker Hold

- Appearance now has one Visual Theme picker: Orbs, Timeline, Dark Knight, M3 Concept. Existing raw values remain unchanged; Timeline is 3. The legacy normal + time-based-orb preference resolves to Timeline. Selecting a theme synchronizes the legacy background and Dark Knight preferences for compatibility.
- The nested Background Effect picker is removed. Timeline retains its preview controls; Dark Knight hides orb controls; Orbs and M3 retain their own rendering and mixing controls.
- Stay memory temporarily disables parking-space recognition without changing the stored VLM preference. Photos are still saved. Recognition is guarded before clipboard access and before starting polling; changing into stay memory dismisses the prompt and cancels active polling, sound, and recognition animation.
- Home parking/stay markers require a 0.6-second hold. Content enlarges to 1.28 times its existing scale during that hold, without altering MapKit's view transform. Successful unlock and release provide haptics subject to the app preference. Early movement, release, or cancellation restores the scale. Global long-press feedback ignores maps so it cannot vibrate before the marker unlocks.
- Verification: standalone theme migration checks; focused simulator tests for theme selection/persistence, M3 controls, marker hold/early movement, and marker scaling; final device build and installation.

This change does not upload another TestFlight build. Build 1.0 (5) already uploaded to TestFlight remains unchanged.
