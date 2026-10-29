-- PostgreSQL foundation only: NOT deployed, no authentication provider wired yet.
-- All tables are private to the server. Mobile clients must use authenticated API.
BEGIN;
CREATE TABLE community_users (
    id uuid PRIMARY KEY,
    auth_subject text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE community_plate_bindings (
    user_id uuid NOT NULL REFERENCES community_users(id) ON DELETE CASCADE,
    plate_key varchar(8) NOT NULL CHECK (plate_key ~ '^[A-HJ-NPR-Z0-9]{1,8}$'),
    display_plate varchar(8) NOT NULL,
    consented_at timestamptz NOT NULL,
    PRIMARY KEY (user_id, plate_key),
    CHECK (replace(display_plate, ' ', '') = plate_key)
);
CREATE INDEX community_plate_recipients ON community_plate_bindings (plate_key);
CREATE TABLE community_threads (
    id uuid PRIMARY KEY,
    plate_key varchar(8) NOT NULL,
    sender_id uuid REFERENCES community_users(id) ON DELETE SET NULL,
    request_key uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    UNIQUE (sender_id, request_key),
    CHECK (expires_at = created_at + interval '168 hours')
);
-- Membership is snapshotted at send time: new bindings never inherit old chats.
CREATE TABLE community_thread_recipients (
    thread_id uuid NOT NULL REFERENCES community_threads(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES community_users(id) ON DELETE CASCADE,
    PRIMARY KEY (thread_id, user_id)
);
CREATE TABLE community_messages (
    id uuid PRIMARY KEY,
    thread_id uuid NOT NULL REFERENCES community_threads(id) ON DELETE CASCADE,
    author_id uuid REFERENCES community_users(id) ON DELETE SET NULL,
    request_key uuid NOT NULL,
    body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 200),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (author_id, request_key)
);
CREATE TABLE community_push_devices (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES community_users(id) ON DELETE CASCADE,
    provider text NOT NULL CHECK (provider IN ('apns', 'fcm')),
    token text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (provider, token)
);
CREATE TABLE community_blocks (
    blocker_id uuid NOT NULL REFERENCES community_users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES community_users(id) ON DELETE CASCADE,
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
CREATE INDEX community_expiry ON community_threads (expires_at);
-- RLS fails closed. The eventual API uses a dedicated server role and must
-- enforce membership and blocking; do not connect mobile clients as table owner.
ALTER TABLE community_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_plate_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_thread_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_blocks ENABLE ROW LEVEL SECURITY;
COMMIT;
