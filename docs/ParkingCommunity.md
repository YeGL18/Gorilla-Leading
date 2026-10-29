# Parking community

## Implemented

The home left-hand controls and adaptive Duo toolbar open a dedicated feature.
First entry offers authorised-driver plate setup or Skip. Later entry opens the
camera. The feature menu contains its own plate settings and shared reminder inbox;
nothing is added to Gorilla Leading's general settings.

VisionKit scans on-device, highlights text and accepts standard plate candidates
on tap. The user must confirm the plate and choose a template before sending.
Custom plates use a restricted keypad. No camera frame is saved or uploaded.
System OCR highlights are not yet the final custom plate-only rounded overlays;
night, rain, reflections and two-line segmentation still require physical testing.

Email OTP login is required only to bind or send, not to scan. Login tokens use
Keychain. Local plate drafts remain explicitly separate from server bindings and
are uploaded only when the user taps Bind. Multiple users may bind the same plate;
removing one user's binding does not affect others. Declaration is consent, not
proof of vehicle ownership. A plate key removes display spaces, pending final
confirmation against official plate examples; the keypad checks syntax, not actual
allocation by the Transport Department.

The shared HTTP backend implements login, bindings, messages, replies, blocks,
reports, account deletion, expiry and a transactional notification outbox. SQLite
is used for this executable single-instance implementation. The former unexecuted
PostgreSQL sketch has been replaced; PostgreSQL migration is not implemented.

## Endpoint contract

Full base URL: `https://YOUR-HOST/v1/parking-community`. JSON requests, JSON errors
`{error: code}`, bearer token except auth/start and auth/verify. See
`backend/parking-community/README.md` for setup; no deployment is configured.

| Endpoint | Contract |
|---|---|
| POST /auth/start | `{email}`; sends OTP, never returns it |
| POST /auth/verify | `{email,code}` → `{token,userId,expiresAt}` |
| POST /auth/logout | Revoke current token |
| GET /me/plates | `{plates:[{plate,consentedAt}]}` |
| POST /me/plates | `{plate,authorisedDriver:true}` |
| DELETE /me/plates/{key} | Remove only caller's binding and revoke recipient history |
| POST /threads | `{plate,text,idempotencyKey}` → `{threadId,expiresAt,status,pushStatus}` |
| GET /threads | `{threads:[{id,plate,expiresAt,lastMessage}]}`, latest 100 |
| GET /threads/{id}/messages | `{messages:[{id,authorId,text,createdAt}],expiresAt}`, latest 200 |
| POST /threads/{id}/messages | `{text,idempotencyKey}` |
| POST /threads/{id}/reports | `{reason}`, requires visible thread |
| POST /blocks | `{userId}`, requires shared visible conversation |
| PUT /me/devices/{installationUUID} | `{provider:"apns"|"fcm",token}`; delivery is not enabled |
| DELETE /me/devices/{installationUUID} | Caller-owned registration only |
| DELETE /me | Delete bindings, sessions, authored content, memberships and devices |

Timestamps are Unix seconds, except `consentedAt` ISO-8601. Send/reply UUID
idempotency keys deduplicate within the retained thread lifetime; altered reuse
returns 409. There is no public plate-existence endpoint; unsuccessful sends still
consume quota to limit enumeration. Recipient counts/identities are not returned.
Message responses expose only opaque participant identifiers for block handling.

One send creates one thread, snapshots current eligible recipients and enqueues one
outbox item per recipient atomically. The sender needs no vehicle binding. All
members see replies. New bindings do not inherit old chats; unbinding permanently
revokes that membership. Blocking filters messages and future delivery.

The three send templates are 小心違例泊車, 留意入返咪錶 and
我幫你墊錢入咗咪錶; custom text is allowed. Replies offer 感謝師兄, 唔該,
多謝提醒 or custom text. The backend enforces 200 Unicode code points per message;
iOS also caps its editor length and surfaces server validation failures.

## Still required before public release

- Provision trusted HTTPS hosting, SMTP and stable secret storage. Validate actual
  OTP delivery; configure Info.plist base URL. No accounts were created externally.
- Implement APNs/FCM workers, device-token lifecycle and app push registration,
  expiry-aware delivery and failure/retry handling. The outbox alone does not send.
- Complete moderation operations, operational monitoring, backup retention and
  deletion verification. UI reports are recorded, not automatically adjudicated.
- Test camera/permissions and complete multi-device acceptance testing on hardware.
- Add recipient-controlled FPS display/jumps and separate developer sponsorship;
  evaluate their platform requirements before activation. No money is processed.

Current UI explicitly says push is unavailable. Connected users can refresh the
shared inbox; there is no claim of real-time receipt. If no API is configured,
login/send stay unavailable. Failed network lookups never become "not registered".
No payment state exists: the advance-payment template is only the sender's claim.
Conversations expire seven days after creation without reply extensions. Logs omit
bodies, plate paths, tokens and OTPs. Stored report content shares thread expiry.

## Verification

- Full iOS build: existing GorillaTranslate scheme, signing disabled for compilation.
- `Tests/ParkingCommunityChecks.swift`: plate syntax, duplicate drafts, persistence,
  deletion and shared API JSON decoding.
- Backend unittest suite: real service transactions, temporary SQLite and HTTP.
