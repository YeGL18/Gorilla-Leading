# Shared parking-community API

Python 3.11+ standard library; no package installation required. This is an
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
`POST /auth/logout` revokes the current session. Bearer auth is required everywhere
else. The iOS token is held in Keychain, scoped by API URL, device-only.

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
APNs/FCM delivery worker or provider credential configuration yet.** Responses say
`pushStatus: not_configured`; the app says push is unavailable and requires manual
inbox refresh. Device registration alone never claims delivery. Unbinding removes
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
