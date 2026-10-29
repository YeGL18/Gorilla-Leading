"""APNs + FCM transports and a session-aware, expiry-aware transactional worker."""
import json
import os
from pathlib import Path
import time
import uuid


class PushFailure(Exception):
    def __init__(self, code, retryable=False, invalid_token=False):
        super().__init__(code)
        self.code, self.retryable, self.invalid_token = code, retryable, invalid_token


class APNs:
    def __init__(self, settings):
        import httpx
        self.key = Path(settings['keyFile']).read_bytes()
        self.key_id, self.team, self.topic = settings['keyId'], settings['teamId'], settings['bundleId']
        self.client = httpx.Client(http2=True, timeout=15)
        self.jwt, self.jwt_at = '', 0

    def send(self, device, thread, message, expires):
        import jwt
        if time.time() - self.jwt_at > 2400:
            self.jwt_at = int(time.time())
            self.jwt = jwt.encode({'iss': self.team, 'iat': self.jwt_at}, self.key,
                                  algorithm='ES256', headers={'kid': self.key_id})
        host = 'api.sandbox.push.apple.com' if device['environment'] == 'sandbox' else 'api.push.apple.com'
        payload = {'aps': {'alert': {'title': '泊車互助提醒', 'body': '你有新的提醒或回覆，撳此查看。'},
                           'sound': 'default', 'thread-id': thread}, 'threadId': thread}
        try:
            response = self.client.post(f'https://{host}/3/device/{device["token"]}', json=payload,
                headers={'authorization': 'bearer ' + self.jwt, 'apns-topic': self.topic,
                         'apns-push-type': 'alert', 'apns-priority': '10',
                         'apns-expiration': str(int(expires)), 'apns-id': message})
        except Exception:
            raise PushFailure('transport_error', retryable=True)
        if response.status_code == 200:
            return
        try:
            reason = response.json().get('reason', '')
        except (ValueError, AttributeError):
            reason = ''
        invalid = response.status_code == 410 or reason in ('BadDeviceToken', 'DeviceTokenNotForTopic')
        raise PushFailure('apns_' + str(response.status_code), response.status_code in (429, 500, 503), invalid)


class FCM:
    def __init__(self, settings):
        import httpx
        from google.oauth2 import service_account
        self.credentials = service_account.Credentials.from_service_account_file(settings['serviceAccountFile'],
            scopes=['https://www.googleapis.com/auth/firebase.messaging'])
        self.project = self.credentials.project_id
        self.client = httpx.Client(timeout=15)

    def send(self, device, thread, message, expires):
        from google.auth.transport.requests import Request
        try:
            if not self.credentials.valid:
                self.credentials.refresh(Request())
            response = self.client.post(f'https://fcm.googleapis.com/v1/projects/{self.project}/messages:send',
                headers={'Authorization': 'Bearer ' + self.credentials.token},
                json={'message': {'token': device['token'], 'data': {'threadId': thread, 'messageId': message},
                    'android': {'priority': 'high', 'ttl': str(max(0, int(expires - time.time()))) + 's'}}})
        except Exception:
            raise PushFailure('transport_error', retryable=True)
        if response.status_code == 200:
            return
        try:
            details = response.json().get('error', {}).get('details', [])
            invalid = any(d.get('errorCode') == 'UNREGISTERED' for d in details if isinstance(d, dict))
        except (ValueError, AttributeError):
            invalid = False
        raise PushFailure('fcm_' + str(response.status_code), response.status_code in (429, 500, 503), invalid)


def load_transports(path):
    if not path or not Path(path).exists():
        return {}
    settings = json.loads(Path(path).read_text())
    providers = {}
    if settings.get('apns', {}).get('keyFile'):
        providers['apns'] = APNs(settings['apns'])
    if settings.get('fcm', {}).get('serviceAccountFile'):
        providers['fcm'] = FCM(settings['fcm'])
    return providers


class Worker:
    def __init__(self, service, transports):
        self.service, self.transports = service, transports

    def tick(self):
        service = self.service
        service.cleanup()
        with service.db() as db:
            # Legacy rows lack a creation-time device snapshot; do not broadcast stale alerts.
            db.execute('INSERT OR IGNORE INTO outbox_prepared SELECT id FROM outbox')
            jobs = [r['id'] for r in db.execute('SELECT id FROM push_jobs WHERE state=\'pending\' AND next_attempt<=? ORDER BY rowid LIMIT 100', (service.clock(),))]
        for job_id in jobs:
            with service.db() as db:
                row = db.execute('''SELECT j.id AS job_id,j.attempts,d.*,ds.environment,o.thread_id,o.message_id,o.expires,
                    o.user_id AS recipient,m.author_id FROM push_jobs j JOIN devices d ON d.id=j.device_id
                    JOIN device_sessions ds ON ds.device_id=d.id JOIN sessions s ON s.digest=ds.session_digest
                    JOIN outbox o ON o.id=j.outbox_id JOIN messages m ON m.id=o.message_id
                    WHERE j.id=? AND s.expires>? AND o.expires>?''', (job_id, service.clock(), service.clock())).fetchone()
                if not row:
                    db.execute('DELETE FROM push_jobs WHERE id=?', (job_id,)); continue
                if row['provider'] not in self.transports:
                    continue  # Configuration may be added later, but never claim delivery.
                try:
                    service.visible(db, row['thread_id'], row['recipient'])
                except Exception:
                    db.execute('DELETE FROM push_jobs WHERE id=?', (job_id,)); continue
                if service.blocked(db, row['recipient'], row['author_id']):
                    db.execute('DELETE FROM push_jobs WHERE id=?', (job_id,)); continue
                device = dict(row)
            try:
                self.transports[device['provider']].send(device, device['thread_id'], device['message_id'], device['expires'])
                with service.db() as db:
                    db.execute('UPDATE push_jobs SET state=\'sent\',attempts=attempts+1,last_code=\'accepted\' WHERE id=?', (job_id,))
            except PushFailure as error:
                with service.db() as db:
                    if error.invalid_token:
                        db.execute('DELETE FROM devices WHERE id=?', (device['id'],))
                    else:
                        attempts = device['attempts'] + 1
                        state = 'pending' if error.retryable and attempts < 6 else 'failed'
                        db.execute('UPDATE push_jobs SET state=?,attempts=?,next_attempt=?,last_code=? WHERE id=?',
                            (state, attempts, service.clock() + min(900, 2 ** attempts * 5), error.code, job_id))
            except Exception:
                # Unexpected errors don't expose provider secrets or crash cleanup.
                with service.db() as db:
                    db.execute('UPDATE push_jobs SET attempts=attempts+1,next_attempt=?,state=CASE WHEN attempts>=5 THEN \'failed\' ELSE \'pending\' END,last_code=\'worker_error\' WHERE id=?', (service.clock() + 60, job_id))
