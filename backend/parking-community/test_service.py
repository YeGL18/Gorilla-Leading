import http.client
import json
import tempfile
import threading
import unittest
import uuid
from http.server import ThreadingHTTPServer
from service import Service, APIError, WEEK, PREFIX, make_handler


class CommunityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = 1800000000.0
        self.mail = {}
        self.api = Service(self.temp.name + '/db.sqlite3', 'test-secret-' * 4,
                           lambda email, code: self.mail.update({email: code}), lambda: self.now)
        self.sender = self.login('sender@example.com')
        self.owner = self.login('owner@example.com')
        self.driver = self.login('driver@example.com')
        self.outsider = self.login('outsider@example.com')

    def tearDown(self):
        self.temp.cleanup()

    def login(self, email):
        self.api.dispatch('POST', '/auth/start', {'email': email}, ip=email)
        result = self.api.dispatch('POST', '/auth/verify', {'email': email, 'code': self.mail[email]}, ip=email)
        return result['token']

    def call(self, session, method, path, **body):
        return self.api.dispatch(method, path, body, session)

    def bind(self, token):
        return self.call(token, 'POST', '/me/plates', plate='AB 1234', authorisedDriver=True)

    def send(self, req=None):
        return self.call(self.sender, 'POST', '/threads', plate='AB1234', text='留意入返咪錶', idempotencyKey=req or str(uuid.uuid4()))

    def expect_error(self, status, fn):
        with self.assertRaises(APIError) as caught:
            fn()
        self.assertEqual(status, caught.exception.status)

    def test_fanout_shared_replies_and_private_access(self):
        self.bind(self.owner)
        self.bind(self.driver)
        thread = self.send()
        tid = thread['threadId']
        for token in [self.sender, self.owner, self.driver]:
            self.assertEqual(tid, self.call(token, 'GET', '/threads')['threads'][0]['id'])
        self.expect_error(404, lambda: self.call(self.outsider, 'GET', f'/threads/{tid}/messages'))
        self.call(self.driver, 'POST', f'/threads/{tid}/messages', text='感謝師兄', idempotencyKey=str(uuid.uuid4()))
        for token in [self.sender, self.owner, self.driver]:
            self.assertEqual(2, len(self.call(token, 'GET', f'/threads/{tid}/messages')['messages']))
        with self.api.db() as db:
            self.assertEqual(4, db.execute('SELECT count(*) FROM outbox').fetchone()[0])
        self.assertEqual('not_configured', thread['pushStatus'])

    def test_unbind_rebind_and_late_binding_do_not_inherit_history(self):
        self.bind(self.owner)
        tid = self.send()['threadId']
        self.bind(self.driver)
        self.expect_error(404, lambda: self.call(self.driver, 'GET', f'/threads/{tid}/messages'))
        self.call(self.owner, 'DELETE', '/me/plates/AB1234')
        self.bind(self.owner)
        self.expect_error(404, lambda: self.call(self.owner, 'GET', f'/threads/{tid}/messages'))

    def test_idempotency_and_payload_conflicts(self):
        self.bind(self.owner)
        req = str(uuid.uuid4())
        first, second = self.send(req), self.send(req)
        self.assertEqual(first, second)
        self.expect_error(409, lambda: self.call(self.sender, 'POST', '/threads', plate='AB1234', text='changed', idempotencyKey=req))
        tid, reply = first['threadId'], str(uuid.uuid4())
        for _ in range(2):
            self.call(self.owner, 'POST', f'/threads/{tid}/messages', text='唔該', idempotencyKey=reply)
        self.expect_error(409, lambda: self.call(self.owner, 'POST', f'/threads/{tid}/messages', text='changed', idempotencyKey=reply))
        self.assertEqual(2, len(self.call(self.owner, 'GET', f'/threads/{tid}/messages')['messages']))
        self.assertEqual(first, self.send(req))

    def test_expiry_deletes_all_content_and_pending_notifications(self):
        self.bind(self.owner)
        tid = self.send()['threadId']
        self.now += WEEK
        self.expect_error(404, lambda: self.call(self.owner, 'GET', f'/threads/{tid}/messages'))
        with self.api.db() as db:
            for table in ['threads', 'messages', 'recipients', 'outbox']:
                self.assertEqual(0, db.execute('SELECT count(*) FROM ' + table).fetchone()[0])

    def test_otp_single_use_attempt_limit_and_session_revocation(self):
        email = 'fresh@example.com'
        self.api.dispatch('POST', '/auth/start', {'email': email}, ip=email)
        code = self.mail[email]
        wrong = '000000' if code != '000000' else '111111'
        for _ in range(5):
            self.expect_error(401, lambda: self.api.dispatch('POST', '/auth/verify', {'email': email, 'code': wrong}, ip=email))
        self.expect_error(401, lambda: self.api.dispatch('POST', '/auth/verify', {'email': email, 'code': code}, ip=email))
        self.expect_error(401, lambda: self.api.dispatch('POST', '/auth/verify', {'email': 'sender@example.com', 'code': self.mail['sender@example.com']}, ip='replay'))
        self.call(self.sender, 'POST', '/auth/logout')
        self.expect_error(401, lambda: self.call(self.sender, 'GET', '/me/plates'))

    def test_missing_recipient_still_counts_against_rate_limit(self):
        for _ in range(20):
            self.expect_error(404, self.send)
        self.expect_error(429, self.send)

    def test_block_and_delete_account(self):
        self.bind(self.owner)
        tid = self.send()['threadId']
        sender_id = self.api.authenticate(self.sender)
        self.call(self.owner, 'POST', '/blocks', userId=sender_id)
        self.expect_error(404, lambda: self.call(self.owner, 'GET', f'/threads/{tid}/messages'))
        self.expect_error(404, self.send)
        self.call(self.sender, 'DELETE', '/me')
        self.expect_error(401, lambda: self.call(self.sender, 'GET', '/threads'))
        with self.api.db() as db:
            self.assertEqual(0, db.execute('SELECT count(*) FROM threads').fetchone()[0])

    def test_binding_limits_and_device_isolation(self):
        self.bind(self.owner)
        self.bind(self.owner)
        self.assertEqual(1, len(self.call(self.owner, 'GET', '/me/plates')['plates']))
        device = str(uuid.uuid4())
        self.call(self.owner, 'PUT', '/me/devices/' + device, provider='apns', token='test-device-token')
        self.call(self.outsider, 'DELETE', '/me/devices/' + device)
        with self.api.db() as db:
            self.assertEqual(1, db.execute('SELECT count(*) FROM devices').fetchone()[0])
        for number in range(19):
            self.call(self.owner, 'POST', '/me/plates', plate='AB' + str(number + 1), authorisedDriver=True)
        self.expect_error(409, lambda: self.call(self.owner, 'POST', '/me/plates', plate='ZZ99', authorisedDriver=True))

    def test_consent_validation_and_http_contract(self):
        self.expect_error(400, lambda: self.call(self.owner, 'POST', '/me/plates', plate='AB1234'))
        self.expect_error(400, lambda: self.call(self.owner, 'POST', '/me/plates', plate='AI1234', authorisedDriver=True))
        server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(self.api))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            client = http.client.HTTPConnection(*server.server_address, timeout=2)
            client.request('GET', PREFIX + '/threads')
            result = client.getresponse()
            self.assertEqual(401, result.status)
            self.assertEqual('no-store', result.getheader('Cache-Control'))
            self.assertEqual('sign_in_required', json.loads(result.read())['error'])
            client.close()
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


if __name__ == '__main__':
    unittest.main()
