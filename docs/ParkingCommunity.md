# Parking community

## Implemented

The home left-hand controls and adaptive Duo toolbar open a dedicated feature.
First entry offers authorised-driver plate setup or Skip. Later entry opens the
camera. The feature menu contains its own plate settings and shared reminder inbox;
nothing is added to Gorilla Leading's general settings.

VisionKit scans on-device and combines nearby letter/number observations, including
two-line layouts and split digit groups. Full-width characters are normalised;
ambiguous O/0 or I/1 characters are never guessed. Numeric-only historical marks
are also accepted as candidates. Candidate plate overlays use translucent rounded
buttons; separate candidate buttons retain a result for four seconds through
tracking drop-outs. Recognition never sends automatically. The user must confirm
the plate and choose a template before sending. Custom plates use a restricted
keypad. A native camera still-photo fallback runs accurate Vision OCR on up to
three alternatives per text observation, using the same spatial parser. Frames
stay in memory and are never saved or uploaded. Night, rain, reflections and real
plate accuracy still require physical testing; this is not a trained ANPR model.

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
| GET /capabilities | Public provider configuration flags; never a delivery receipt |
| GET /me/plates | `{plates:[{plate,consentedAt}]}` |
| POST /me/plates | `{plate,authorisedDriver:true}` |
| DELETE /me/plates/{key} | Remove only caller's binding and revoke recipient history |
| POST /threads | `{plate,text,idempotencyKey}` → `{threadId,expiresAt,status,pushStatus}` |
| GET /threads | `{threads:[{id,plate,expiresAt,lastMessage}]}`, latest 100 |
| GET /threads/{id}/messages | `{messages:[{id,authorId,text,createdAt}],expiresAt}`, latest 200 |
| POST /threads/{id}/messages | `{text,idempotencyKey}` |
| POST /threads/{id}/reports | `{reason}`, requires visible thread |
| POST /blocks | `{userId}`, requires shared visible conversation |
| PUT /me/devices/{installationUUID} | `{provider:"apns"|"fcm",token,environment?}`; session-bound registration |
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
  OTP delivery; configure Info.plist base URL. Firebase Spark project was created for trial.
- Configure APNs/FCM private credentials and Apple push-capable provisioning, then
  test real delivery. Transport workers, session-bound registration, device snapshots,
  expiry checks and retry handling are implemented; credentials are not bundled.
- Complete moderation operations, operational monitoring, backup retention and
  deletion verification. UI reports are recorded, not automatically adjudicated.
- Test camera/permissions and complete multi-device acceptance testing on hardware.
- Add recipient-controlled FPS display/jumps and separate developer sponsorship;
  evaluate their platform requirements before activation. No money is processed.

Current UI detects missing push configuration and explains manual refresh.
Configured queues/provider acceptance do not prove device receipt. If no API is configured,
login/send stay unavailable. Failed network lookups never become "not registered".
No payment state exists: the advance-payment template is only the sender's claim.
Conversations expire seven days after creation without reply extensions. Logs omit
bodies, plate paths, tokens and OTPs. Stored report content shares thread expiry.

## Verification

- Full iOS build: existing GorillaTranslate scheme, signing disabled for compilation.
- `Tests/ParkingCommunityChecks.swift`: plate syntax, duplicate drafts, persistence,
  deletion and shared API JSON decoding.
- Backend unittest suite: real service transactions, temporary SQLite and HTTP.
