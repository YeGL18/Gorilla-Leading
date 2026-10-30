# Gorilla Leading Android parking trial

Native Android 8+ client for the shared parking-community backend. This is a
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
Use a stable backend URL for production; recreating a Quick Tunnel requires a new
build and, because login tokens are scoped to the API URL, a fresh login.

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
