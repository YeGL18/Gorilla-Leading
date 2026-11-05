-- Executable SQLite schema for the single-instance API. Not a deployed service.
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE);
CREATE TABLE IF NOT EXISTS challenges (
 email TEXT PRIMARY KEY, digest TEXT NOT NULL, expires REAL NOT NULL,
 attempts INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
 digest TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 expires REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS bindings (
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 plate_key TEXT NOT NULL, plate TEXT NOT NULL, consented_at TEXT NOT NULL,
 PRIMARY KEY(user_id, plate_key)
);
CREATE INDEX IF NOT EXISTS binding_lookup ON bindings(plate_key);
CREATE TABLE IF NOT EXISTS threads (
 id TEXT PRIMARY KEY, plate TEXT NOT NULL,
 sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_key TEXT NOT NULL, created REAL NOT NULL, expires REAL NOT NULL,
 UNIQUE(sender_id, request_key)
);
CREATE TABLE IF NOT EXISTS recipients (
 thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 PRIMARY KEY(thread_id, user_id)
);
CREATE TABLE IF NOT EXISTS messages (
 id TEXT PRIMARY KEY, thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
 author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_key TEXT NOT NULL, body TEXT NOT NULL CHECK(length(body) BETWEEN 1 AND 200),
 created REAL NOT NULL, UNIQUE(author_id, request_key)
);
CREATE TABLE IF NOT EXISTS devices (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 provider TEXT NOT NULL CHECK(provider IN ('apns','fcm')), token TEXT NOT NULL,
 UNIQUE(provider,token)
);
CREATE TABLE IF NOT EXISTS blocks (
 blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 PRIMARY KEY(blocker_id, blocked_id), CHECK(blocker_id <> blocked_id)
);
CREATE TABLE IF NOT EXISTS reports (
 id TEXT PRIMARY KEY, thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 reason TEXT NOT NULL CHECK(length(reason) BETWEEN 1 AND 500), created REAL NOT NULL
);
-- Transactional outbox: registering a device does not mean push is connected.
CREATE TABLE IF NOT EXISTS outbox (
 id TEXT PRIMARY KEY, thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
 message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 created REAL NOT NULL, expires REAL NOT NULL, UNIQUE(message_id,user_id)
);
CREATE TABLE IF NOT EXISTS rate_limits (
 scope TEXT PRIMARY KEY, started REAL NOT NULL, count INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS apple_challenges (
 digest TEXT PRIMARY KEY, nonce_hash TEXT NOT NULL, purpose TEXT NOT NULL,
 user_id TEXT REFERENCES users(id) ON DELETE CASCADE, expires REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS apple_identities (
 subject TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS apple_tokens (
 digest TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 encrypted TEXT NOT NULL
);
-- Keeps only encrypted revocation credentials after deletion, no account/plate data.
CREATE TABLE IF NOT EXISTS apple_revocations (
 digest TEXT PRIMARY KEY, encrypted TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
 next_attempt REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS thread_expiry ON threads(expires);
-- Device ownership is tied to the session that registered it. Logout revokes it.
CREATE TABLE IF NOT EXISTS device_sessions (
 device_id TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
 session_digest TEXT NOT NULL REFERENCES sessions(digest) ON DELETE CASCADE,
 environment TEXT NOT NULL DEFAULT 'production' CHECK(environment IN ('sandbox','production'))
);
CREATE TABLE IF NOT EXISTS outbox_prepared (
 outbox_id TEXT PRIMARY KEY REFERENCES outbox(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS push_jobs (
 id TEXT PRIMARY KEY,
 outbox_id TEXT NOT NULL REFERENCES outbox(id) ON DELETE CASCADE,
 device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','sent','failed')),
 attempts INTEGER NOT NULL DEFAULT 0, next_attempt REAL NOT NULL DEFAULT 0,
 last_code TEXT, UNIQUE(outbox_id,device_id)
);
