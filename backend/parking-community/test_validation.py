import hashlib
import tempfile
import unittest
from pathlib import Path
from android_release import AndroidRelease
from service import APIError, Service


class ValidationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.mail = {}
        self.api = Service(Path(self.temp.name) / 'test.db', 'x' * 32,
                           lambda email, code: self.mail.update({email: code}))
        self.sender = self.login('sender@example.test')
        self.owner = self.login('owner@example.test')

    def tearDown(self):
        self.temp.cleanup()

    def login(self, email):
        self.api.dispatch('POST', '/auth/start', {'email': email}, ip=email)
        return self.api.dispatch('POST', '/auth/verify', {'email': email, 'code': self.mail[email]}, ip=email)

    def call(self, account, method, path, **body):
        return self.api.dispatch(method, path, body, account['token'])

    def test_lookup_before_send_does_not_create_messages_or_expose_identity(self):
        self.assertEqual({'available': False}, self.call(self.sender, 'POST', '/plates/lookup', plate='AB1234'))
        self.call(self.owner, 'POST', '/me/plates', plate='AB 1234', authorisedDriver=True)
        self.assertEqual({'available': True}, self.call(self.sender, 'POST', '/plates/lookup', plate='AB1234'))
        self.assertEqual({'available': False}, self.call(self.owner, 'POST', '/plates/lookup', plate='AB1234'))
        with self.api.db() as db:
            self.assertEqual(0, db.execute('SELECT count(*) FROM messages').fetchone()[0])
            db.execute('INSERT INTO blocks VALUES (?,?)', (self.owner['userId'], self.sender['userId']))
        self.assertEqual({'available': False}, self.call(self.sender, 'POST', '/plates/lookup', plate='AB1234'))
        with self.assertRaises(APIError) as error:
            self.api.dispatch('POST', '/plates/lookup', {'plate': 'AB1234'})
        self.assertEqual(401, error.exception.status)

    def test_lookup_has_independent_rate_limit(self):
        for _ in range(30):
            self.call(self.sender, 'POST', '/plates/lookup', plate='AB1234')
        with self.assertRaises(APIError) as error:
            self.call(self.sender, 'POST', '/plates/lookup', plate='AB1234')
        self.assertEqual(429, error.exception.status)

    def test_initial_message_and_reply_have_stable_ownership(self):
        import uuid
        self.call(self.owner, 'POST', '/me/plates', plate='AB1234', authorisedDriver=True)
        key = str(uuid.uuid4())
        sent = self.call(self.sender, 'POST', '/threads', plate='AB1234', text='hello', idempotencyKey=key)
        self.assertEqual(sent, self.call(self.sender, 'POST', '/threads', plate='AB1234', text='hello', idempotencyKey=key))
        tid = sent['threadId']
        reply = self.call(self.owner, 'POST', f'/threads/{tid}/messages', text='thanks', idempotencyKey=str(uuid.uuid4()))
        mine = self.call(self.sender, 'GET', f'/threads/{tid}/messages')['messages']
        theirs = self.call(self.owner, 'GET', f'/threads/{tid}/messages')['messages']
        self.assertEqual(sent['messageId'], mine[0]['id'])
        self.assertEqual(reply['id'], mine[1]['id'])
        self.assertEqual([True, False], [m['mine'] for m in mine])
        self.assertEqual([False, True], [m['mine'] for m in theirs])
        self.assertEqual({'userId': self.sender['userId']}, self.call(self.sender, 'GET', '/me/session'))

    def test_server_probe_and_explicit_release(self):
        info = self.api.dispatch('GET', '/capabilities', {})
        self.assertEqual('gorilla-parking-community', info['service'])
        self.assertEqual(1, info['apiVersion'])
        self.assertEqual({'available': False}, self.api.dispatch('GET', '/android/update', {}))
        apk = Path(self.temp.name) / 'fixture.apk'
        apk.write_bytes(b'not a real APK; metadata test only')
        self.api.android_release = AndroidRelease(apk, 4, '0.4-test')
        manifest = self.api.dispatch('GET', '/android/update', {})
        self.assertEqual(4, manifest['versionCode'])
        self.assertEqual(hashlib.sha256(apk.read_bytes()).hexdigest(), manifest['sha256'])
        self.assertNotIn('path', manifest)

    def test_apk_http_route_serves_only_configured_file(self):
        import http.client
        import threading
        from http.server import ThreadingHTTPServer
        from service import make_handler, PREFIX
        apk = Path(self.temp.name) / 'fixture.apk'
        payload = b'fixture APK bytes'
        apk.write_bytes(payload)
        self.api.android_release = AndroidRelease(apk, 4, '0.4-test')
        server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(self.api))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
            connection.request('GET', PREFIX + '/android/apk?file=unrelated-private-file')
            response = connection.getresponse()
            self.assertEqual(200, response.status)
            self.assertEqual('no-store', response.getheader('Cache-Control'))
            self.assertEqual('application/vnd.android.package-archive', response.getheader('Content-Type'))
            self.assertEqual(payload, response.read())
            connection.close()
        finally:
            server.shutdown(); server.server_close(); worker.join(timeout=5)


if __name__ == '__main__':
    unittest.main()
