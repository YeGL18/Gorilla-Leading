"""Parking community reference API. SQLite, email OTP, opaque bearer sessions.

Use a TLS reverse proxy and a single service instance. Optional APNs/FCM workers
require local credentials; storage and provider acceptance are not delivery receipts.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import smtplib
import sqlite3
import ssl
import threading
import time
import uuid
from contextlib import contextmanager
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PREFIX = '/v1/parking-community'
WEEK = 7 * 24 * 3600
PLATE = re.compile(r'^[A-HJ-NPR-Z0-9 ]{1,8}$')


class APIError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code
        super().__init__(code)


def require(condition, code='invalid_request', status=400):
    if not condition:
        raise APIError(status, code)


def plate_value(value):
    require(isinstance(value, str) and PLATE.fullmatch(value) and value.strip())
    return value.strip(), value.replace(' ', '')


def text_value(value, maximum=200):
    require(isinstance(value, str) and 1 <= len(value.strip()) <= maximum)
    return value.strip()


def request_key(value):
    try:
        return str(uuid.UUID(value))
    except (TypeError, ValueError, AttributeError):
        raise APIError(400, 'invalid_idempotency_key')


class Service:
    def __init__(self, database, secret, deliver, clock=time.time, providers=None, android_release=None, apple=None):
        require(len(secret) >= 32, 'server_secret_too_short', 500)
        self.database, self.secret, self.deliver, self.clock = str(database), secret.encode(), deliver, clock
        self.providers = providers or {}
        self.android_release = android_release
        self.apple = apple
        self.lock = threading.RLock()
        with self.db() as db:
            db.executescript(Path(__file__).with_name('schema.sql').read_text())

    @contextmanager
    def db(self):
        # Serialize read-modify-write transactions for this single-instance service.
        with self.lock:
            db = sqlite3.connect(self.database, timeout=10)
            db.row_factory = sqlite3.Row
            db.execute('PRAGMA foreign_keys=ON')
            db.execute('PRAGMA secure_delete=ON')
            try:
                with db:
                    yield db
            finally:
                db.close()

    def digest(self, value):
        return hmac.new(self.secret, value.encode(), hashlib.sha256).hexdigest()

    def limit(self, db, scope, count, window):
        now = self.clock()
        row = db.execute('SELECT * FROM rate_limits WHERE scope=?', (scope,)).fetchone()
        if not row or now - row['started'] >= window:
            db.execute('INSERT OR REPLACE INTO rate_limits VALUES (?,?,1)', (scope, now))
        else:
            require(row['count'] < count, 'rate_limited', 429)
            db.execute('UPDATE rate_limits SET count=count+1 WHERE scope=?', (scope,))

    def authenticate(self, token):
        with self.db() as db:
            row = db.execute('SELECT user_id FROM sessions WHERE digest=? AND expires>?',
                             (self.digest(token), self.clock())).fetchone()
        require(row is not None, 'sign_in_required', 401)
        return row['user_id']

    def start_login(self, body, ip):
        email = body.get('email', '')
        require(isinstance(email, str) and len(email) <= 254 and re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email))
        email = email.strip().lower()
        code = f'{secrets.randbelow(1000000):06d}'
        now = self.clock()
        with self.db() as db:
            self.limit(db, 'login-ip:' + self.digest(ip), 10, 3600)
            self.limit(db, 'login-email:' + self.digest(email), 1, 60)
            db.execute('INSERT OR REPLACE INTO challenges VALUES (?,?,?,0,?)',
                       (email, self.digest(email + ':' + code), now + 600, now))
        try:
            self.deliver(email, code)
        except Exception:
            with self.db() as db:
                db.execute('DELETE FROM challenges WHERE email=? AND digest=?', (email, self.digest(email + ':' + code)))
            raise APIError(503, 'email_unavailable')
        return {'status': 'code_sent', 'expiresIn': 600}

    def finish_login(self, body, ip):
        email, code = body.get('email', ''), body.get('code', '')
        require(isinstance(email, str) and isinstance(code, str) and re.fullmatch('[0-9]{6}', code))
        email = email.strip().lower()
        valid = False
        with self.db() as db:
            self.limit(db, 'verify-ip:' + self.digest(ip), 30, 3600)
            row = db.execute('SELECT * FROM challenges WHERE email=?', (email,)).fetchone()
            if row and row['expires'] > self.clock() and row['attempts'] < 5:
                db.execute('UPDATE challenges SET attempts=attempts+1 WHERE email=?', (email,))
                valid = hmac.compare_digest(row['digest'], self.digest(email + ':' + code))
            if valid:
                db.execute('DELETE FROM challenges WHERE email=?', (email,))
                user = db.execute('SELECT id FROM users WHERE email=?', (email,)).fetchone()
                uid = user['id'] if user else str(uuid.uuid4())
                if not user:
                    db.execute('INSERT INTO users VALUES (?,?)', (uid, email))
                token = secrets.token_urlsafe(32)
                expires = self.clock() + 30 * 86400
                db.execute('INSERT INTO sessions VALUES (?,?,?)', (self.digest(token), uid, expires))
        # Invalid attempts must commit; raising inside the transaction rolls them back.
        require(valid, 'invalid_or_expired_code', 401)
        return {'token': token, 'userId': uid, 'expiresAt': expires}

    def cleanup(self):
        with self.db() as db:
            db.execute('DELETE FROM apple_challenges WHERE expires<=?', (self.clock(),))
            now = self.clock()
            db.execute('DELETE FROM threads WHERE expires<=?', (now,))
            db.execute('DELETE FROM sessions WHERE expires<=?', (now,))
            db.execute('DELETE FROM devices WHERE id NOT IN (SELECT device_id FROM device_sessions)')
            db.execute('DELETE FROM challenges WHERE expires<=?', (now,))
            db.execute('DELETE FROM rate_limits WHERE started<?', (now - 86400,))

    def blocked(self, db, left, right):
        return db.execute('SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)',
                          (left, right, right, left)).fetchone() is not None

    def visible(self, db, thread_id, uid):
        thread = db.execute('SELECT * FROM threads WHERE id=? AND expires>?', (thread_id, self.clock())).fetchone()
        require(thread is not None, 'thread_unavailable', 404)
        member = thread['sender_id'] == uid or db.execute('SELECT 1 FROM recipients WHERE thread_id=? AND user_id=?',
                                                         (thread_id, uid)).fetchone()
        require(member and not self.blocked(db, uid, thread['sender_id']), 'thread_unavailable', 404)
        return thread

    def enqueue(self, db, thread, mid, author):
        members = {thread['sender_id']}
        members.update(r['user_id'] for r in db.execute('SELECT user_id FROM recipients WHERE thread_id=?', (thread['id'],)))
        for uid in members - {author}:
            if not self.blocked(db, author, uid) and not self.blocked(db, uid, thread['sender_id']):
                outbox_id = str(uuid.uuid4())
                db.execute('INSERT INTO outbox VALUES (?,?,?,?,?,?)',
                           (outbox_id, thread['id'], mid, uid, self.clock(), thread['expires']))
                # Snapshot devices at message creation; later installations receive no stale alerts.
                devices = db.execute('SELECT d.id FROM devices d JOIN device_sessions ds ON ds.device_id=d.id JOIN sessions s ON s.digest=ds.session_digest WHERE d.user_id=? AND s.expires>?', (uid, self.clock())).fetchall()
                db.executemany('INSERT INTO push_jobs(id,outbox_id,device_id) VALUES (?,?,?)',
                               [(str(uuid.uuid4()), outbox_id, device['id']) for device in devices])
                db.execute('INSERT INTO outbox_prepared VALUES (?)', (outbox_id,))

    def message_result(self, row, uid):
        return {'id': row['id'], 'authorId': row['author_id'], 'mine': row['author_id'] == uid, 'text': row['body'], 'createdAt': row['created']}

    def apple_challenge(self, body, token, ip):
        require(self.apple is not None, 'apple_unavailable', 503)
        purpose = body.get('purpose', 'login')
        require(purpose in ['login', 'link'])
        uid = self.authenticate(token) if purpose == 'link' else None
        nonce, challenge = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        with self.db() as db:
            self.limit(db, 'apple-challenge:' + self.digest(ip), 20, 3600)
            db.execute('DELETE FROM apple_challenges WHERE expires<=?', (self.clock(),))
            if uid:
                session = db.execute('SELECT expires FROM sessions WHERE digest=?', (self.digest(token),)).fetchone()
                require(session and session['expires'] - 30 * 86400 >= self.clock() - 300, 'recent_login_required', 401)
                self.limit(db, 'apple-link:' + uid, 5, 3600)
            db.execute('INSERT INTO apple_challenges VALUES (?,?,?,?,?)',
                       (self.digest(challenge), hashlib.sha256(nonce.encode()).hexdigest(), purpose, uid, self.clock() + 300))
        return {'challengeId': challenge, 'nonce': nonce, 'expiresIn': 300}

    def apple_login(self, body, token, ip):
        require(self.apple is not None, 'apple_unavailable', 503)
        challenge = body.get('challengeId')
        require(isinstance(challenge, str) and 1 <= len(challenge) <= 128)
        with self.db() as db:
            self.limit(db, 'apple-verify:' + self.digest(ip), 30, 3600)
            row = db.execute('SELECT * FROM apple_challenges WHERE digest=? AND expires>?',
                             (self.digest(challenge), self.clock())).fetchone()
        require(row is not None, 'apple_challenge_expired', 401)
        uid = self.authenticate(token) if row['purpose'] == 'link' else None
        require(row['purpose'] != 'link' or uid == row['user_id'], 'apple_verification_failed', 401)
        try:
            subject, refresh = self.apple.exchange(body.get('identityToken'), body.get('authorizationCode'), row['nonce_hash'])
            encrypted = self.apple.encrypt(refresh)
        except (ValueError, TypeError, KeyError):
            raise APIError(401, 'apple_verification_failed')
        except Exception:
            raise APIError(503, 'apple_unavailable')
        with self.db() as db:
            # Consume the server challenge once, after Apple verifies both tokens.
            found = db.execute('DELETE FROM apple_challenges WHERE digest=? AND expires>?',
                               (self.digest(challenge), self.clock())).rowcount
            require(found == 1, 'apple_challenge_expired', 401)
            existing = db.execute('SELECT user_id FROM apple_identities WHERE subject=?', (subject,)).fetchone()
            if uid:
                require(not existing or existing['user_id'] == uid, 'apple_already_linked', 409)
                other = db.execute('SELECT subject FROM apple_identities WHERE user_id=?', (uid,)).fetchone()
                require(not other or other['subject'] == subject, 'apple_already_linked', 409)
            elif existing:
                uid = existing['user_id']
            else:
                uid = str(uuid.uuid4())
                # Apple-only accounts have no email-based login until explicitly linked.
                db.execute('INSERT INTO users VALUES (?,?)', (uid, 'apple:' + self.digest(subject)))
            db.execute('INSERT OR IGNORE INTO apple_identities VALUES (?,?)', (subject, uid))
            db.execute('INSERT OR IGNORE INTO apple_tokens VALUES (?,?,?)', (self.digest(refresh), uid, encrypted))
            session = secrets.token_urlsafe(32)
            expires = self.clock() + 30 * 86400
            db.execute('INSERT INTO sessions VALUES (?,?,?)', (self.digest(session), uid, expires))
        return {'token': session, 'userId': uid, 'expiresAt': expires}

    def revoke_apple_pending(self):
        if self.apple is None:
            return
        with self.db() as db:
            rows = db.execute('SELECT * FROM apple_revocations WHERE next_attempt<=? LIMIT 4', (self.clock(),)).fetchall()
        for row in rows:
            try:
                self.apple.revoke_encrypted(row['encrypted'])
            except Exception:
                with self.db() as db:
                    db.execute('UPDATE apple_revocations SET attempts=attempts+1,next_attempt=? WHERE digest=?',
                               (self.clock() + min(3600, 15 * 2 ** min(row['attempts'], 8)), row['digest']))
            else:
                with self.db() as db:
                    db.execute('DELETE FROM apple_revocations WHERE digest=?', (row['digest'],))

    def dispatch(self, method, path, body, token='', ip='local'):
        require(isinstance(body, dict))
        if method == 'GET' and path == '/capabilities':
            return {'service': 'gorilla-parking-community', 'apiVersion': 1,
                    'features': ['recipient_lookup', 'message_ownership'],
                    'auth': {'apple': self.apple is not None},
                    'push': {p: p in self.providers for p in ['apns','fcm']}}
        if method == 'POST' and path == '/auth/start':
            return self.start_login(body, ip)
        if method == 'POST' and path == '/auth/verify':
            return self.finish_login(body, ip)
        if method == 'POST' and path == '/auth/apple/challenge':
            return self.apple_challenge(body, token, ip)
        if method == 'POST' and path == '/auth/apple':
            return self.apple_login(body, token, ip)
        if method == 'GET' and path == '/android/update':
            return self.android_release.manifest() if self.android_release else {'available': False}
        uid = self.authenticate(token)
        self.cleanup()
        if method == 'POST' and path == '/plates/lookup':
            # Exact, authenticated, rate-limited availability only; never expose owners.
            with self.db() as db:
                self.limit(db, 'lookup:' + uid, 30, 3600)
                _, key = plate_value(body.get('plate'))
                available = any(not self.blocked(db, uid, r['user_id']) for r in db.execute(
                    'SELECT user_id FROM bindings WHERE plate_key=? AND user_id<>?', (key, uid)))
            return {'available': available}
        if method == 'POST':
            with self.db() as db:
                if path == '/threads':
                    self.limit(db, 'send:' + uid, 20, 3600)
                elif path == '/me/plates':
                    self.limit(db, 'bind:' + uid, 30, 3600)
                elif path.endswith('/messages'):
                    self.limit(db, 'reply:' + uid, 60, 3600)
        with self.db() as db:
            if path == '/me/session' and method == 'GET':
                return {'userId': uid}
            if path == '/auth/logout' and method == 'POST':
                db.execute('DELETE FROM devices WHERE id IN (SELECT device_id FROM device_sessions WHERE session_digest=?)', (self.digest(token),))
                db.execute('DELETE FROM sessions WHERE digest=?', (self.digest(token),))
                return {'status': 'signed_out'}
            if path == '/me' and method == 'DELETE':
                db.execute('INSERT OR IGNORE INTO apple_revocations (digest,encrypted) SELECT digest,encrypted FROM apple_tokens WHERE user_id=?', (uid,))
                db.execute('DELETE FROM users WHERE id=?', (uid,))
                return {'status': 'deleted'}
            if path == '/me/plates':
                if method == 'GET':
                    return {'plates': [dict(r) for r in db.execute('SELECT plate,consented_at AS consentedAt FROM bindings WHERE user_id=? ORDER BY plate_key', (uid,))]}
                if method == 'POST':
                    plate, key = plate_value(body.get('plate'))
                    require(body.get('authorisedDriver') is True, 'consent_required')
                    existing = db.execute('SELECT 1 FROM bindings WHERE user_id=? AND plate_key=?', (uid, key)).fetchone()
                    count = db.execute('SELECT count(*) FROM bindings WHERE user_id=?', (uid,)).fetchone()[0]
                    require(existing or count < 20, 'plate_limit_reached', 409)
                    # Store server-observed consent time, not a client-asserted timestamp.
                    consent = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(self.clock()))
                    db.execute('INSERT OR IGNORE INTO bindings VALUES (?,?,?,?)', (uid, key, plate, consent))
                    return {'status': 'bound'}
            if path.startswith('/me/plates/') and method == 'DELETE':
                _, key = plate_value(path.rsplit('/', 1)[-1])
                db.execute('DELETE FROM recipients WHERE user_id=? AND thread_id IN (SELECT id FROM threads WHERE replace(plate,\' \',\'\')=?)', (uid, key))
                db.execute('DELETE FROM outbox WHERE user_id=? AND thread_id IN (SELECT id FROM threads WHERE replace(plate,\' \',\'\')=?)', (uid, key))
                db.execute('DELETE FROM bindings WHERE user_id=? AND plate_key=?', (uid, key))
                return {'status': 'unbound'}
            if path == '/threads' and method == 'POST':
                plate, key = plate_value(body.get('plate'))
                text, req = text_value(body.get('text')), request_key(body.get('idempotencyKey'))
                old = db.execute('SELECT * FROM threads WHERE sender_id=? AND request_key=?', (uid, req)).fetchone()
                if old:
                    first = db.execute('SELECT id,body FROM messages WHERE thread_id=? ORDER BY rowid LIMIT 1', (old['id'],)).fetchone()
                    require(old['plate'] == plate and first and first['body'] == text, 'idempotency_conflict', 409)
                    return {'threadId': old['id'], 'messageId': first['id'], 'expiresAt': old['expires'], 'status': 'accepted', 'pushStatus': 'queued' if self.providers else 'not_configured'}
                recipients = [r['user_id'] for r in db.execute('SELECT user_id FROM bindings WHERE plate_key=? AND user_id<>?', (key, uid)) if not self.blocked(db, uid, r['user_id'])]
                require(recipients, 'recipient_unavailable', 404)
                tid, mid, now = str(uuid.uuid4()), str(uuid.uuid4()), self.clock()
                db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?)', (tid, plate, uid, req, now, now + WEEK))
                db.executemany('INSERT INTO recipients VALUES (?,?)', [(tid, r) for r in recipients])
                db.execute('INSERT INTO messages VALUES (?,?,?,?,?,?)', (mid, tid, uid, req, text, now))
                thread = db.execute('SELECT * FROM threads WHERE id=?', (tid,)).fetchone()
                self.enqueue(db, thread, mid, uid)
                return {'threadId': tid, 'messageId': mid, 'expiresAt': now + WEEK, 'status': 'accepted', 'pushStatus': 'queued' if self.providers else 'not_configured'}
            if path == '/threads' and method == 'GET':
                rows = db.execute('SELECT DISTINCT t.* FROM threads t LEFT JOIN recipients r ON r.thread_id=t.id WHERE (t.sender_id=? OR r.user_id=?) AND t.expires>? ORDER BY t.created DESC,t.id LIMIT 100', (uid, uid, self.clock())).fetchall()
                result = []
                for row in rows:
                    if self.blocked(db, uid, row['sender_id']):
                        continue
                    last = db.execute('SELECT * FROM messages WHERE thread_id=? AND author_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=? UNION SELECT blocker_id FROM blocks WHERE blocked_id=?) ORDER BY created DESC,rowid DESC LIMIT 1', (row['id'], uid, uid)).fetchone()
                    result.append({'id': row['id'], 'plate': row['plate'], 'createdAt': row['created'], 'expiresAt': row['expires'], 'lastMessage': self.message_result(last, uid) if last else None})
                return {'threads': result}
            parts = path.strip('/').split('/')
            if len(parts) == 3 and parts[0] == 'threads' and parts[2] == 'messages':
                thread = self.visible(db, parts[1], uid)
                if method == 'GET':
                    rows = db.execute('SELECT * FROM (SELECT rowid AS sequence,* FROM messages WHERE thread_id=? AND author_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id=? UNION SELECT blocker_id FROM blocks WHERE blocked_id=?) ORDER BY rowid DESC LIMIT 200) ORDER BY sequence', (parts[1], uid, uid))
                    return {'messages': [self.message_result(r, uid) for r in rows], 'expiresAt': thread['expires']}
                if method == 'POST':
                    text, req = text_value(body.get('text')), request_key(body.get('idempotencyKey'))
                    old = db.execute('SELECT * FROM messages WHERE author_id=? AND request_key=?', (uid, req)).fetchone()
                    if old:
                        require(old['thread_id'] == thread['id'] and old['body'] == text, 'idempotency_conflict', 409)
                        return {'id': old['id'], 'status': 'accepted', 'pushStatus': 'queued' if self.providers else 'not_configured'}
                    mid = str(uuid.uuid4())
                    db.execute('INSERT INTO messages VALUES (?,?,?,?,?,?)', (mid, thread['id'], uid, req, text, self.clock()))
                    self.enqueue(db, thread, mid, uid)
                    return {'id': mid, 'status': 'accepted', 'pushStatus': 'queued' if self.providers else 'not_configured'}
            if len(parts) == 3 and parts[0] == 'threads' and parts[2] == 'reports' and method == 'POST':
                self.visible(db, parts[1], uid)
                self.limit(db, 'report:' + uid, 10, 3600)
                db.execute('INSERT INTO reports VALUES (?,?,?,?,?)', (str(uuid.uuid4()), parts[1], uid, text_value(body.get('reason'), 500), self.clock()))
                return {'status': 'reported'}
            if path == '/blocks' and method == 'POST':
                other = body.get('userId')
                require(isinstance(other, str) and other != uid)
                shared = db.execute('SELECT t.id FROM threads t JOIN messages m ON m.thread_id=t.id WHERE m.author_id=?', (other,)).fetchall()
                allowed = False
                for row in shared:
                    try:
                        self.visible(db, row['id'], uid)
                        allowed = True
                    except APIError:
                        pass
                require(allowed, 'user_unavailable', 404)
                db.execute('INSERT OR IGNORE INTO blocks VALUES (?,?)', (uid, other))
                db.execute('DELETE FROM outbox WHERE (user_id=? AND message_id IN (SELECT id FROM messages WHERE author_id=?)) OR (user_id=? AND message_id IN (SELECT id FROM messages WHERE author_id=?))', (uid, other, other, uid))
                return {'status': 'blocked'}
            if len(parts) == 3 and parts[:2] == ['me', 'devices']:
                # Namespaced by account, preventing another user deleting a known ID.
                device_id = uid + ':' + request_key(parts[2])
                if method == 'DELETE':
                    db.execute('DELETE FROM devices WHERE id=? AND user_id=?', (device_id, uid))
                    return {'status': 'removed'}
                if method == 'PUT':
                    provider, device_token = body.get('provider'), body.get('token')
                    require(provider in ['apns', 'fcm'] and isinstance(device_token, str) and 1 <= len(device_token) <= 4096)
                    db.execute('DELETE FROM devices WHERE provider=? AND token=? AND id<>?', (provider, device_token, device_id))
                    db.execute('INSERT INTO devices VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET provider=excluded.provider,token=excluded.token', (device_id, uid, provider, device_token))
                    environment = body.get('environment', 'production')
                    require(environment in ['sandbox','production'])
                    db.execute('INSERT INTO device_sessions VALUES (?,?,?) ON CONFLICT(device_id) DO UPDATE SET session_digest=excluded.session_digest,environment=excluded.environment', (device_id, self.digest(token), environment))
                    return {'status': 'registered', 'pushStatus': 'queued' if self.providers else 'not_configured'}
        raise APIError(404, 'not_found')


def smtp_deliver(email, code):
    host, sender = os.environ['COMMUNITY_SMTP_HOST'], os.environ['COMMUNITY_MAIL_FROM']
    message = EmailMessage()
    message['Subject'] = 'Gorilla Leading 登入驗證碼'
    message['From'], message['To'] = sender, email
    message.set_content(f'登入驗證碼：{code}\n10 分鐘內有效。\n只在你剛剛開啟的 Gorilla Leading App 輸入。'
                        '\n我們不會透過電話、訊息或客服要求你透露驗證碼。'
                        '\n若非你要求登入，請忽略；不要將驗證碼交給其他人。')
    with smtplib.SMTP(host, int(os.getenv('COMMUNITY_SMTP_PORT', '587')), timeout=15) as smtp:
        smtp.starttls(context=ssl.create_default_context())
        if os.getenv('COMMUNITY_SMTP_USER'):
            smtp.login(os.environ['COMMUNITY_SMTP_USER'], os.environ['COMMUNITY_SMTP_PASSWORD'])
        smtp.send_message(message)


def make_handler(service):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # Never log plate paths, emails, tokens, codes or message bodies.

        def handle_api(self):
            try:
                parsed = urlparse(self.path)
                require(parsed.path.startswith(PREFIX + '/'), 'not_found', 404)
                if self.command == 'GET' and parsed.path == PREFIX + '/android/apk':
                    require(service.android_release is not None, 'not_found', 404)
                    metadata = service.android_release.manifest()
                    with service.android_release.path.open('rb') as source:
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/vnd.android.package-archive')
                        self.send_header('Content-Length', str(metadata['bytes']))
                        self.send_header('Cache-Control', 'no-store')
                        self.send_header('X-Content-Type-Options', 'nosniff')
                        self.end_headers()
                        while chunk := source.read(65536):
                            self.wfile.write(chunk)
                    return
                length = int(self.headers.get('Content-Length', '0'))
                require(0 <= length <= 16384, 'request_too_large', 413)
                require(not self.headers.get('Transfer-Encoding'), 'invalid_request')
                body = json.loads(self.rfile.read(length)) if length else {}
                auth = self.headers.get('Authorization', '')
                token = auth[7:] if auth.startswith('Bearer ') else ''
                result = service.dispatch(self.command, parsed.path[len(PREFIX):], body, token, self.client_address[0])
                status = 200
            except APIError as error:
                status, result = error.status, {'error': error.code}
            except (ValueError, UnicodeError, TypeError):
                status, result = 400, {'error': 'invalid_request'}
            except Exception:
                status, result = 500, {'error': 'internal_error'}
            payload = json.dumps(result, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(payload)

        do_GET = do_POST = do_PUT = do_DELETE = handle_api
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default=str(Path(__file__).with_name('community.sqlite3')))
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    secret = os.environ.get('COMMUNITY_SECRET', '')
    if len(secret) < 32:
        parser.error('Set COMMUNITY_SECRET to a stable random value of at least 32 characters')
    if not os.environ.get('COMMUNITY_SMTP_HOST') or not os.environ.get('COMMUNITY_MAIL_FROM'):
        parser.error('Configure COMMUNITY_SMTP_HOST and COMMUNITY_MAIL_FROM before enabling login')
    os.umask(0o077)
    from push import load_transports, Worker
    try:
        transports = load_transports(os.environ.get('COMMUNITY_PUSH_CONFIG', ''))
    except Exception:
        parser.error('Push configuration could not be loaded; check local key paths and dependencies. No key values logged.')
    from android_release import AndroidRelease
    from apple_identity import AppleIdentity
    try:
        apple = AppleIdentity.configured(secret)
    except Exception:
        parser.error('Apple sign-in configuration could not be loaded. No key values logged.')
    service = Service(args.db, secret, smtp_deliver, providers=transports, android_release=AndroidRelease.configured(), apple=apple)
    service.cleanup()
    stop = threading.Event()
    def cleanup_worker():
        while not stop.wait(60):
            try:
                service.cleanup()
            except sqlite3.Error:
                print('Retention cleanup failed', flush=True)
    threading.Thread(target=cleanup_worker, daemon=True).start()
    def apple_revocation_worker():
        while not stop.wait(2):
            try:
                service.revoke_apple_pending()
            except Exception:
                print('Apple authorization revocation pending; no credentials logged', flush=True)
    if apple:
        threading.Thread(target=apple_revocation_worker, daemon=True).start()
    worker = Worker(service, transports)
    def push_worker():
        while not stop.wait(2):
            try:
                worker.tick()
            except Exception:
                print('Push worker iteration failed; no private payload logged', flush=True)
    if transports:
        threading.Thread(target=push_worker, daemon=True).start()
    server = ThreadingHTTPServer((args.host, args.port), make_handler(service))
    try:
        server.serve_forever()
    finally:
        stop.set()
        server.server_close()


if __name__ == '__main__':
    main()
