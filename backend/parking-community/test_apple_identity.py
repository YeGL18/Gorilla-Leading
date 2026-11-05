import hashlib
import tempfile
import unittest
from pathlib import Path
from service import APIError, Service


class AppleFixture:
    def __init__(self):
        self.codes = {}
        self.revoked = []
        self.fail_revoke = False

    def exchange(self, token, code, nonce):
        subject, expected_nonce = self.codes.get(code, (None, None))
        if not subject or token != 'signed-fixture-' + code or nonce != expected_nonce:
            raise ValueError('Invalid fixture credential')
        return subject, 'refresh-' + code

    def encrypt(self, token):
        return 'fixture-encrypted-' + hashlib.sha256(token.encode()).hexdigest()

    def revoke_encrypted(self, encrypted):
        if self.fail_revoke:
            raise OSError('Offline')
        self.revoked.append(encrypted)


class AppleLoginChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.now = 1800000000
        self.mail = {}
        self.apple = AppleFixture()
        self.api = Service(Path(self.temp.name) / 'test.sqlite3', 'x' * 32,
                           lambda email, code: self.mail.update({email: code}),
                           clock=lambda: self.now, apple=self.apple)
        self.sequence = 0

    def tearDown(self):
        self.temp.cleanup()

    def call(self, method, path, body=None, token=''):
        return self.api.dispatch(method, path, body or {}, token, ip='fixture-client')

    def error(self, code, action):
        with self.assertRaises(APIError) as caught:
            action()
        self.assertEqual(code, caught.exception.code)

    def email_login(self, email):
        self.call('POST', '/auth/start', {'email': email})
        return self.call('POST', '/auth/verify', {'email': email, 'code': self.mail[email]})

    def credential(self, subject, purpose='login', token=''):
        challenge = self.call('POST', '/auth/apple/challenge', {'purpose': purpose}, token)
        self.sequence += 1
        code = 'fixture-code-' + str(self.sequence)
        self.apple.codes[code] = (subject, hashlib.sha256(challenge['nonce'].encode()).hexdigest())
        return {'challengeId': challenge['challengeId'], 'identityToken': 'signed-fixture-' + code, 'authorizationCode': code}

    def test_apple_subject_is_stable_and_never_silently_merges_email(self):
        email = self.email_login('existing@example.test')
        first = self.call('POST', '/auth/apple', self.credential('apple-subject'))
        second = self.call('POST', '/auth/apple', self.credential('apple-subject'))
        self.assertEqual(first['userId'], second['userId'])
        self.assertNotEqual(email['userId'], first['userId'])
        self.assertNotEqual(first['token'], second['token'])
        with self.api.db() as db:
            values = [r[0] for r in db.execute('SELECT encrypted FROM apple_tokens')]
            self.assertTrue(values)
            self.assertTrue(all('refresh-' not in value for value in values))

    def test_recent_authenticated_link_preserves_existing_user_and_bindings(self):
        email = self.email_login('existing@example.test')
        self.call('POST', '/me/plates', {'plate': 'AB1234', 'authorisedDriver': True}, email['token'])
        linked = self.call('POST', '/auth/apple', self.credential('linked-apple', 'link', email['token']), email['token'])
        self.assertEqual(email['userId'], linked['userId'])
        signed_in = self.call('POST', '/auth/apple', self.credential('linked-apple'))
        self.assertEqual(email['userId'], signed_in['userId'])
        self.assertEqual('AB1234', self.call('GET', '/me/plates', token=signed_in['token'])['plates'][0]['plate'])
        other = self.email_login('other@example.test')
        self.error('apple_already_linked', lambda: self.call('POST', '/auth/apple',
                   self.credential('linked-apple', 'link', other['token']), other['token']))

    def test_link_requires_recent_login_and_cannot_use_another_accounts_challenge(self):
        first = self.email_login('first@example.test')
        second = self.email_login('second@example.test')
        credential = self.credential('linked', 'link', first['token'])
        self.error('apple_verification_failed', lambda: self.call('POST', '/auth/apple', credential, second['token']))
        self.now += 301
        self.error('recent_login_required', lambda: self.credential('linked', 'link', first['token']))

    def test_expiry_replay_and_bad_nonce_are_rejected(self):
        credential = self.credential('new-apple')
        self.call('POST', '/auth/apple', credential)
        self.error('apple_challenge_expired', lambda: self.call('POST', '/auth/apple', credential))
        expired = self.credential('expired')
        self.now += 301
        self.error('apple_challenge_expired', lambda: self.call('POST', '/auth/apple', expired))
        wrong = self.credential('wrong-nonce')
        self.apple.codes[wrong['authorizationCode']] = ('wrong-nonce', 'different-nonce')
        self.error('apple_verification_failed', lambda: self.call('POST', '/auth/apple', wrong))
        with self.api.db() as db:
            self.assertEqual(1, db.execute('SELECT count(*) FROM apple_identities').fetchone()[0])

    def test_delete_removes_data_and_retries_apple_revocation_without_plain_tokens(self):
        user = self.call('POST', '/auth/apple', self.credential('deleted-user'))
        self.call('DELETE', '/me', token=user['token'])
        self.error('sign_in_required', lambda: self.call('GET', '/me/plates', token=user['token']))
        with self.api.db() as db:
            for table in ['users', 'apple_identities', 'apple_tokens', 'sessions']:
                self.assertEqual(0, db.execute('SELECT count(*) FROM ' + table).fetchone()[0])
            self.assertEqual(1, db.execute('SELECT count(*) FROM apple_revocations').fetchone()[0])
        self.apple.fail_revoke = True
        self.api.revoke_apple_pending()
        self.assertFalse(self.apple.revoked)
        self.now += 16; self.apple.fail_revoke = False
        self.api.revoke_apple_pending()
        self.assertEqual(1, len(self.apple.revoked))
        with self.api.db() as db:
            self.assertEqual(0, db.execute('SELECT count(*) FROM apple_revocations').fetchone()[0])


try:
    import jwt
    from cryptography.hazmat.primitives.asymmetric import rsa, ec
    from cryptography.hazmat.primitives import serialization
    CRYPTO = True
except ImportError:
    CRYPTO = False


@unittest.skipUnless(CRYPTO, 'Install requirements-push.txt for real JWT verification checks')
class AppleCryptoChecks(unittest.TestCase):
    def test_real_signatures_nonce_audience_expiry_and_encrypted_storage(self):
        import time
        from types import SimpleNamespace
        from apple_identity import AppleIdentity
        with tempfile.TemporaryDirectory() as directory:
            signing = ec.generate_private_key(ec.SECP256R1())
            private = Path(directory) / 'fixture.p8'
            private.write_bytes(signing.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            provider = AppleIdentity({'clientId': 'com.gorilla.translation', 'teamId': 'fixture-team',
                                     'keyId': 'fixture-key', 'privateKeyPath': str(private)}, 'x' * 32)
            apple_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
            provider.keys = SimpleNamespace(get_signing_key_from_jwt=lambda token: SimpleNamespace(key=apple_key.public_key()))
            claims = {'iss': 'https://appleid.apple.com', 'aud': 'com.gorilla.translation',
                      'sub': 'fixture-subject', 'nonce': 'fixture-nonce', 'iat': int(time.time()), 'exp': int(time.time()) + 300}
            token = jwt.encode(claims, apple_key, algorithm='RS256')
            self.assertEqual('fixture-subject', provider.claims(token, 'fixture-nonce')['sub'])
            for changed in [{'aud': 'another-app'}, {'iss': 'https://attacker.invalid'}, {'exp': int(time.time()) - 60}, {'nonce': 'wrong'}]:
                with self.assertRaises(Exception):
                    provider.claims(jwt.encode({**claims, **changed}, apple_key, algorithm='RS256'), 'fixture-nonce')
            rogue = rsa.generate_private_key(public_exponent=65537, key_size=2048)
            with self.assertRaises(Exception):
                provider.claims(jwt.encode(claims, rogue, algorithm='RS256'), 'fixture-nonce')
            secret = provider.client_secret()
            verified = jwt.decode(secret, signing.public_key(), algorithms=['ES256'], audience=provider.issuer)
            self.assertEqual('com.gorilla.translation', verified['sub'])
            ciphertext = provider.encrypt('fixture-refresh-token')
            self.assertNotIn('fixture-refresh-token', ciphertext)
            self.assertEqual(b'fixture-refresh-token', provider.cipher.decrypt(ciphertext.encode()))


if __name__ == '__main__':
    unittest.main()
