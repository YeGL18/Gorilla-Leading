# Parking community — implementation boundary

## Current iOS implementation

Home left controls (and adaptive Duo toolbar) open a dedicated full-screen feature.
First entry presents plate setup with an explicit skip; subsequent entry opens the
camera. Its own toolbar contains plate management and notification permissions.

Plate setup uses a restricted keypad and requires an authorised-driver declaration.
Drafts are local UserDefaults data, labelled as drafts, deletable by swipe. They
are not server bindings. This version has no login, recipient lookup, messages,
remote push, FPS integration or sponsorship. Send is disabled, never simulated.

VisionKit DataScanner runs live on-device OCR with system highlights. Tapping a
standard-format result opens confirmation and template selection. No frames are
saved or uploaded. Custom plates use the keypad. This is an OCR baseline, not a
trained ANPR model: two-line segmentation, low light and reflective plates require
physical-device evaluation. System highlights are not yet the final custom rounded
plate-only overlays. Camera denial, unsupported devices and scanner errors retain
manual entry; backgrounding and presented child screens remove the scanner.

The three fixed templates are 小心違例泊車, 留意入返咪錶,
我幫你墊錢入咗咪錶. Custom text is capped at 200 Swift characters.

## Shared backend contract (not a deployed service)

HTTPS JSON `/v1/parking-community` is shared by iOS and Android. An identity provider
must supply verified bearer tokens; the API derives the user ID from its token,
never from request JSON. No plate is required to register or send. Both clients
must implement the same validation, access, retention and blocking rules. APNs and
FCM registration differs only in the device endpoint. Provider secrets stay server-side.

| Endpoint | Request / response |
|---|---|
| GET /me/plates | Authenticated user's bindings only |
| POST /me/plates | `{plate, consentedAt}`; idempotent per user + plate key |
| DELETE /me/plates/{key} | Remove only caller's binding; revoke recipient access to its threads |
| POST /threads | `{plate, text, idempotencyKey}`; return `{threadId, expiresAt, status:"accepted"}` |
| GET /threads | Caller-visible unexpired threads; cursor pagination |
| GET /threads/{id}/messages | Sender or retained, currently bound recipient; cursor pagination |
| POST /threads/{id}/messages | `{text, idempotencyKey}`; same membership check |
| PUT /me/devices/{installationId} | `{provider:"apns"|"fcm", token}`; associate token with current login |
| DELETE /me/devices/{installationId} | Unregister at logout; revoke server token access |
| POST /blocks | `{userId}` resolved from an existing visible thread |
| POST /threads/{id}/reports | `{reason}`; requires thread visibility; moderation storage policy needed |
| DELETE /me | Delete bindings/devices, revoke identity and thread memberships; remove authored content |

Do not ship an unauthenticated bulk plate-lookup API. Sending must validate a
recipient exists before creating a thread; no match returns `recipient_unavailable`,
without recipient counts, identities or activity. Authenticated send can still be
used to enumerate plates: quotas, server-side rate limits, blocking and abuse
monitoring are launch requirements. The final limits require trial calibration.
No client should turn an unavailable service into "plate not registered".

## Data and transaction rules

`backend/parking-community/schema.sql` is a PostgreSQL starting schema, not an
operating backend. `PRIMARY KEY(user_id, plate_key)` permits many people to bind
the same plate while deduplicating each person's binding. Display spaces are
preserved; lookup keys omit them. This assumes spacing does not identify a separate
registration: confirm against authoritative plate examples before launch. The
keypad is syntax validation, not evidence of an officially allocated mark.

Send runs in one transaction: authenticate, validate, enforce blocks/quotas, find
current bindings excluding the sender, create one thread and message, snapshot
eligible recipients, and enqueue one push per active device using a transactional
outbox (outbox/worker implementation pending). Never create one conversation per
recipient. Replies go to the original sender and all still-eligible recipients;
new bindings cannot read past threads. Unbinding revokes recipient access
immediately. Account deletion cannot leave a copied identity or message body.

Every reply rechecks membership, current binding, blocks and expiry. An idempotent
retry cannot create duplicate messages or notifications; mismatched reuse returns
conflict. Push acceptance is not delivery. Expire push TTL at thread expiry and
avoid stale alerts. Push payloads use opaque thread IDs and generic previews until
a user has opted into displaying content on the lock screen.

Threads expire 168 hours after creation, replies do not extend expiry. Reads deny
expired records immediately. A monitored cleanup worker cascades deletion of
messages/recipients and cancels queued pushes. Logs must omit bodies, plates and
tokens; caches, crash reports and backups require documented expiry and deletion
verification. No historical-message premium feature may bypass this policy.

No payment state exists: "I paid" is a user's assertion. External FPS support,
recipient-controlled disclosure and developer sponsorship remain separate future
integration work. There is no bank callback or verified repayment status.

## Before activation

Choose/provision identity provider and PostgreSQL hosting; implement the API,
transactional push outbox, APNs/FCM credentials, membership checks, delete worker,
reports and block handling. Deploy in staging and verify fan-out on two accounts,
unbinding/rebinding, retry idempotency, expiry and unauthorised reads. Then wire the
Swift protocol and Android client. Never enable Send just because camera OCR works.

## Verification

`swiftc GorillaTranslate/Models/ParkingCommunity.swift Tests/ParkingCommunityChecks.swift -o /tmp/parking-community-checks`

Run the binary to check exact matching, restricted characters, line breaks,
duplicate drafts, restoration and deletion. Full iOS build uses the existing
GorillaTranslate scheme. Actual camera accuracy, highlighting, permissions and
background recovery must be checked on a supported physical iPhone; a successful
build does not establish real-world ANPR performance.
