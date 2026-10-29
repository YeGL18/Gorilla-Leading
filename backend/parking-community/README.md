# Shared parking-community API

Python 3.11+; the API uses the standard library, with optional push dependencies. This is an
implemented single-instance backend, not a deployed or production-certified service.
SQLite schema is installed at startup. No fake login and no OTP-returning endpoint.

## Run

Set these environment variables in your process manager / secret store:

- `COMMUNITY_SECRET`: stable cryptographically random secret, at least 32 characters.
  Rotating it invalidates all sessions/challenges. Never commit it.
- `COMMUNITY_SMTP_HOST`, `COMMUNITY_SMTP_PORT` (default 587), `COMMUNITY_MAIL_FROM`.
- `COMMUNITY_SMTP_USER`, `COMMUNITY_SMTP_PASSWORD` if required by the mail provider.
  SMTP requires STARTTLS; there is no plaintext downgrade.

```
python3 backend/parking-community/service.py --db /private/tmp/community.sqlite3
```

Default binding: `127.0.0.1:8787`. Expose only through a TLS reverse proxy with
connection/body timeouts, request and connection limits. This stdlib HTTP listener
is for development or a controlled single-instance service; harden the hosting
stack before public launch. The service ignores forwarded-IP headers, so reverse
proxy deployments must account for shared proxy IP quotas before release. Do not
scale multiple processes around the current in-process transaction lock.

API base: `/v1/parking-community`. iOS reads `ParkingCommunityAPIBaseURL` from
Info.plist (full base URL, including that suffix). Debug builds may override it
with Xcode launch environment `GORILLA_COMMUNITY_API_URL`, e.g.
`http://localhost:8787/v1/parking-community` on the simulator. HTTP is accepted only
for loopback in Debug. Physical devices need a trusted HTTPS endpoint. A blank
configuration disables login and send; it never falls back to a demo server.

## Authentication

`POST /auth/start {email}` sends a random six-digit OTP to the supplied address.
`POST /auth/verify {email,code}` creates or signs into that account and returns
`{token,userId,expiresAt}`. Tokens are opaque, 30-day sessions; only keyed digests
are stored. OTPs are keyed digests, single-use, ten-minute expiry, five attempts.
`POST /auth/logout` revokes the current session. Bearer auth is required for user data; `/capabilities` is also public. The iOS token is held in Keychain, scoped by API URL, device-only.

Each account may bind up to 20 plates; binding mutations are rate-limited.
Auth/send/reply rate limits are testable initial limits, not calibrated production
thresholds. Email delivery happens only when a real user requests a code; tests
inject an in-memory mail sink. No test sends email to external recipients.

## Features

See `docs/ParkingCommunity.md` for endpoint and membership details. Bind requires
`{plate,authorisedDriver:true}` and records server time. Multiple accounts may bind
the same plate. Threads are shared by a snapshot of recipients and the sender.
New bindings cannot read old threads; unbinding revokes received thread access,
even after rebinding. Exact plate matching only; no transport-register lookup.

Messages expire 168 hours after thread creation; replies cannot extend the window.
A minute-based cleanup worker removes expired threads and cascades their content,
reports and pending pushes. Reads enforce expiry even if cleanup is delayed.
SQLite secure-delete is enabled, but hosting disk snapshots/backups still need a
retention policy; take no unbounded database backups. Rate-limit keys expire too.
Reports are stored pending moderation and expire with the thread; no moderation
console or emergency support exists yet.

A transaction writes both message and notification-outbox rows. **There is no
APNs/FCM delivery without provider credentials.** The optional worker now sends
through APNs HTTP/2 or FCM HTTP v1, with per-device retries and invalid-token cleanup.
Responses use `queued` only when a provider is configured, otherwise `not_configured`;
neither means delivered. `GET /capabilities` is public and lists enabled providers.
Device snapshots are taken at message creation, so a later installation receives
no stale alerts. Session expiry/logout, unbinding and blocks cancel pending jobs.
Notification payloads carry opaque thread/message IDs and a generic alert, with
no plate or message body. Device registration alone never claims delivery. Unbinding removes
queued notices. Block relationships prevent new delivery and hide blocked content.

Latest-list limits are 100 threads and 200 messages; pagination is not implemented.
No FPS payments, verified money states, developer sponsorship or nearby broadcasts.

## Tests

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s backend/parking-community -v
```

Tests use temporary databases and an ephemeral loopback HTTP listener. They cover
OTP attempt limits/replay, sessions, multiple recipients/shared replies, access
control, unbind/rebind, idempotency conflicts, no-match enumeration quotas, blocking,
account deletion and seven-day cascade deletion. They do not prove mail delivery,
push delivery, bank interoperability, or public-hosting security.

## Free local iPhone trial

Run `python3 backend/parking-community/run_local.py --init` to create the ignored,
0600-permission `.env.local.json`. Fill only `gmailAddress` and `gmailAppPassword`
locally; preserve `serverSecret`. A Gmail app password is 16 characters (spaces
between groups are accepted), requires two-step verification, and must not be
shared in chat or committed. `--check-smtp` verifies authentication without sending
an email. `--wait-for-config` waits for saved configuration, then starts the API.

A Cloudflare Quick Tunnel may expose only port 8787 for development. Its temporary
HTTPS address changes when recreated; the Mac, backend and tunnel must stay running.
Build the phone app with `PARKING_COMMUNITY_API_BASE_URL=https://YOUR-TEMP-HOST/v1/parking-community`.
Info.plist expands this build setting; no temporary host needs to be committed.
Without a configured address the normal build keeps login/send disabled. This
setup tests account/binding/conversation flows. Real push also needs the configuration below.


## Remote push setup

Install dependencies in an isolated environment:

```
python3 -m venv backend/parking-community/.venv
backend/parking-community/.venv/bin/pip install -r backend/parking-community/requirements-push.txt
```

Store private keys only in the ignored `backend/parking-community/.push/` directory,
with directory permission 0700 and file permission 0600. Never put them in the APK,
iOS bundle, screenshots, logs, or Git. Use a dedicated FCM-only service account for
production; a Firebase Admin SDK private key has broader access than messaging.
The local runner automatically loads `.push/config.json` if present. Direct service
launches instead set `COMMUNITY_PUSH_CONFIG` to its absolute path.

Example config (omit any unconfigured provider):

```json
{
  "fcm": {"serviceAccountFile": "/absolute/path/to/firebase-service-account.json"},
  "apns": {
    "keyFile": "/absolute/path/to/AuthKey.p8",
    "keyId": "APPLE_KEY_ID",
    "teamId": "APPLE_TEAM_ID",
    "bundleId": "com.gorilla.translation"
  }
}
```

Restart the backend after adding credentials. `/capabilities` should then show the
configured provider as true; this is configuration detection, not a delivery test.
Do not generate replacement keys repeatedly when a browser download fails: retain
only a successfully saved key and revoke inaccessible/unused keys in Google Cloud.

Android: register package `com.gorilla.leading` in the same Firebase project,
place its downloaded `google-services.json` at `android/app/google-services.json`
(ignored), then rebuild. The JSON project ID must match the server credential.
The APK uses Firebase Messaging only, no Firebase Analytics. Login, allow system
notifications, then use the notification button in feature settings to register.
The current debug APK is for internal testing, not store distribution.

Apple: enable Push Notifications for App ID `com.gorilla.translation`, sign into
Xcode with the owning developer account, and regenerate the provisioning profile.
Create/download an APNs signing key and configure its key ID/team ID above. Debug
builds register in the sandbox, Release in production. The app routes a tapped
notification into the referenced shared conversation, including cold launch.

Verify with two actual signed-in devices/accounts: bind one plate to both owner
accounts, send from a third account, receive background alerts on both platforms,
tap through to the same thread, reply, and test logout/unbind/block cancellation.
The automated queue tests use fake transports; they do not prove APNs/FCM delivery.
The Mac must stay awake with both service and tunnel running during this trial.

Primary integration references: [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[Android message handling](https://firebase.google.com/docs/cloud-messaging/android/receive),
[APNs provider requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns).
