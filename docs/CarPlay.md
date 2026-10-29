# Gorilla Leading CarPlay

## Scope

- Native parking summary: status, duration (hours:minutes), current parking location, floor and space number.
- Nearby vacant parking meters only, limited to 12 entries within the existing configured meter-map radius.
- No parking-lot directory, speedometer, animation, photography, record editing or manual departure actions on the car screen.
- Selecting a meter opens its details with a Navigate action. The action calls `CPTemplateApplicationScene.open` with an Apple Maps driving-directions URL, targeting the CarPlay display rather than the iPhone screen.
- Apple Maps owns route selection, starting guidance, and the navigation UI. This app does not claim navigation entitlement or provide its own guidance.

## Apple Approval Required

Source integration and scene registration do not grant CarPlay access. The normal signing entitlements intentionally remain unchanged, so ordinary iPhone development and distribution builds continue to sign successfully.

1. Request the **Parking** CarPlay app entitlement for `com.gorilla.translation` from the Apple Developer account owner.
2. Describe parking-session information, nearby available metered spaces, and handoff to Apple Maps. Do not describe this as an independent navigation app.
3. After approval, enable the approved capability for the App ID and regenerate development/distribution profiles.
4. Only then add the following key to `GorillaTranslate/GorillaTranslate.entitlements`:

```xml
<key>com.apple.developer.carplay-parking</key>
<true/>
```

5. Rebuild and test on a real CarPlay unit or Apple's CarPlay Simulator in Xcode Device Hub. Installing the current unsigned-for-CarPlay feature code alone will not add a Gorilla icon to the car screen.

## Verification

- Confirm iPhone's existing SwiftUI window and navigation remain functional after adding the CarPlay scene configuration.
- Connect and disconnect repeatedly, including while Apple Maps is frontmost. Periodic refreshes stop when the CarPlay scene is inactive or disconnected.
- Verify after first unlock with iPhone locked; before protected data becomes available, no previous session should be invented.
- Verify automatic parking, manually started sessions, adjusted entry times, manual departure, a genuinely new visit and a non-driving stay. An ended or non-driving session must not expose previous parking-space details.
- Verify meter states: fresh vacant, occupied, incompatible vehicle, stale, absent location and disabled meter detection. Unknown or expired data is never advertised as a vacancy.
- Tap a fresh vacant meter's Navigate action and confirm Apple Maps appears on the **car display** with the correct destination and driving route. Apple Maps may require route/start confirmation. Check failure handling with unavailable Maps/network as well.
- Repeat the handoff with iPhone locked and with Apple Maps already guiding to a different destination. The request is explicitly user-initiated and must not be issued in the background.
- Test both touchscreen and rotary-input cars. No code depends on free-form touch gestures or a keyboard.

## Official References

- [CarPlay Developer Guide](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf), 2026-10-13: parking category and templates, ten-second minimum periodic UI-refresh interval, and “Launching other apps in CarPlay” (page 30).
- [Request CarPlay access](https://developer.apple.com/carplay/)
- [Apple Maps links](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html)
