# Gorilla Leading Android parking trial

Native Android 15+ (minSdk 35) client for the shared parking-community backend. This is a
parking-only trial, not a port of all iOS driving/navigation functionality.
Includes CameraX + bundled on-device ML Kit OCR, restricted plate entry, email OTP,
shared plate binding, reminder templates/custom messages, inbox/replies, reporting,
blocking and account deletion. OCR results remain selectable for four seconds;
check the plate before sending. No photos are uploaded. No FPS integration yet.

Place Firebase Android config at `app/google-services.json` (ignored). Never put
server credentials in this folder. Without that config the app explicitly says
remote push is unavailable. The backend separately needs its FCM private key.

Build using Java 17+ and Android SDK 35:

```
./gradlew -PcommunityApiUrl=https://YOUR-HOST/v1/parking-community assembleDebug testDebugUnitTest
```

The APK is `app/build/outputs/apk/debug/app-debug.apk`. It is signed with the local
debug key for internal use. `dist/GorillaLeading-parking-test.apk` is a delivery copy.
Use a stable backend URL for production. A new Quick Tunnel URL can be entered in
Settings without rebuilding; login tokens remain scoped to the URL, so a new
address requires a fresh login.

FCM high-priority data messages create private generic notifications; the plate
and message content are fetched only after authenticated app opening. Android 13+
requires notification permission. Device registration is retried when the app
resumes. Provider acceptance is not proof of delivery; test with real devices.


Reply fixes (0.2-test): quick phrases fill a draft; the fixed bottom “發送回覆”
button submits it explicitly and remains available while messages scroll. Sending
locks the editor to prevent accidental duplicate submissions and retains a failed
request's draft/idempotency key. The visible inbox/thread refreshes every five
seconds, stops on pause, and does not rebuild the editor. Foreground refresh is a
fallback only; background notifications still require real FCM/APNs credentials.

UI polish (0.2-test): floating capsule tab bar (主頁/對話/設定) with a selection
pill; Android 13+ gets real liquid-glass refraction via QmDeve
AndroidLiquidGlassView (the Kyant0/AndroidLiquidGlass “Catalog” is Compose-only
and cannot be used in this View app), older versions get a translucent capsule
fallback. Predictive back preview (conversation → inbox, others → home; back on
home exits the app), edge-to-edge windows with systemBars+IME inset handling and
cutout short-edges (no white strips at the status/gesture bars), message bubbles
labelled 你/對方 with per-message times, inbox cards with relative timestamps and
你：/對方： previews, redesigned reply footer (quick chips + rounded input +
circular send). Xiaomi/MIUI: per-app display settings may force immersive or
theme-engine skins; the app consumes insets correctly, so pick 預設/沉浸式 display
mode per-app if a theme reskins the bars — deeper MIUI quirks to be handled later.

Backend note: service.py now returns `mine` on messages and `createdAt` on
thread-list entries. Re-sync service.py to the Windows backend and restart it so
clients can mark 你/對方 without relying on the Android local fallback.

UI polish 2 (0.2-test): iOS-style animated light-orb background copied from
GorillaTranslate/Views/AnimatedBackground.swift (LegacyOrbField) — three soft
orbs (BEBC3F/5CAEB7/0098FF preset 0, diameters 450/500/420, opacity 0.3, the
same sin/cos drift parameters) over a light gradient, drawn by OrbBackground
(an animated Drawable set as the content background, 25fps, plusLighter overlap
via ADD xfermode, RadialGradient standing in for the iOS blur). The glass
tab-bar capsule now refracts these moving orbs, so the liquid-glass effect is
visible; stronger refraction/dispersion/tint, a top glint + white border
(Ui.glassSheen), and elevation shadow make the capsule read as glass on every
API level (richer frosted fallback below Android 13). The tab bar now stays on
login/onboarding/plate/composer screens (only the conversation keeps its own
composer footer); the selection pill follows the last top-level tab. Buttons
use a two-tier system in Ui (primaryButton: gold gradient CTA;
secondaryButton: white card with gold hairline), applied across home, login,
settings, plate entry, composer, and ScannerActivity (返回／手動輸入 and 確認
buttons, rounded camera preview, density-correct paddings).

UI polish 3 (0.2-test): palette replaced — the old mustard/brown scheme
(GOLD #936A17 on cream) is gone; the app now uses clean cool neutrals
(BG #F3F5F6, INK #1C2126, MUTED #6E7A82) with a deep teal accent
(#0E7490, primary CTA gradient #1495A8→#0B6273) and light-teal chat
bubbles (MINE #DCEFF2 / MINE_INK #0B4F58); theme colorAccent and
windowBackground follow. Scroll-truncation fix on tab screens: the
ScrollView now reaches the physical display bottom so scrolling content
slides off the screen edge naturally (passing under the floating glass
capsule) instead of being hard-cut in the visible strip below the tab
bar; bottom clearance (sys.bottom+148dp) lives in the ScrollView's own
padding (clipToPadding=false) so the last item rests above the capsule.

SDK floor (0.2-test): minSdk raised 26 → 35 (Android 15), so every install
target has AGSL/RenderEffect, predictive-back progress, cutout and notification
permission APIs. All `Build.VERSION` guards are removed (cutout short-edges,
navigation-bar contrast, POST_NOTIFICATIONS request/check, liquid-glass gate);
liquid glass is now always the real refraction path and `Ui.glassFallback`
remains only as an initialization-failure fallback. The QmDeve liquidglass
dependency stays pinned at 1.0.3 because 1.0.4+ require compileSdk 37
(unrelated to minSdk). versionCode 2 / versionName '0.2-test' unchanged.

## Interface revision, 2026-11-01

This revision supersedes the older UI-polish notes above:

- One persistent orb backdrop and one persistent, width-capped dark-glass tab bar.
  Pages no longer recreate the entire window or selection indicator when tabs change.
- Predictive back reveals the actual retained parent page. The page host clips the
  parent outside the moving foreground page, keeping the background stationary and
  preventing labels from bleeding through the transparent foreground.
- Restrained blue primary actions, neutral secondary surfaces, native rounded
  confirmation dialogs, press feedback and bundled Lucide toolbar icons/licenses.
- Outgoing messages align right; received messages align left. Bubble text uses
  intrinsic width with a maximum, not a match-parent label inside a wrap-content bubble.
- Existing drafts and retry idempotency keys survive page navigation. Drafts and
  retained account pages are cleared when signing out, deleting an account or changing
  the tunnel address. Messages are not persisted by the new page stack.
- Android keeps QmDeve AndroidLiquidGlassView 1.0.3; it does not claim to use the
  Compose Catalog. The instrumentation check asserts real glass binding succeeds.
- `CommunityUiTest` uses explicitly gated debug fixtures with no credentials or
  backend sends. It checks message width/alignment, retained roots/tabs, predictive
  cancellation/commit and draft retention, and saves screenshots under the app's
  external-files `ui-checks` directory. Run only on an isolated emulator.

Build and unit checks: `./gradlew assembleDebug assembleDebugAndroidTest testDebugUnitTest`.
Install the two APKs on the selected emulator, then run
`adb -s EMULATOR_SERIAL shell am instrument -w com.gorilla.leading.test/androidx.test.runner.AndroidJUnitRunner`.
