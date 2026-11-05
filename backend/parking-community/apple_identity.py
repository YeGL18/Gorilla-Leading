"""Apple-native authorization-code exchange, verification and token revocation.

Only fixed Apple HTTPS endpoints are used. The private key never enters a client.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import time
from urllib import request, parse


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class AppleIdentity:
    issuer = 'https://appleid.apple.com'

    def __init__(self, config, secret):
        import jwt
        from cryptography.fernet import Fernet
        self.config = config
        self.client_id = config['clientId']
        self.team_id, self.key_id = config['teamId'], config['keyId']
        self.private_key = Path(config['privateKeyPath']).read_text()
        # Fail at startup if the downloaded key is not a valid signing key.
        from cryptography.hazmat.primitives.serialization import load_pem_private_key
        from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePrivateKey, SECP256R1
        key = load_pem_private_key(self.private_key.encode(), password=None)
        if not isinstance(key, EllipticCurvePrivateKey) or not isinstance(key.curve, SECP256R1):
            raise ValueError('Apple signing key must be P-256')
        self.jwt = jwt
        self.keys = jwt.PyJWKClient(self.issuer + '/auth/keys', cache_jwk_set=True, lifespan=3600, timeout=10)
        encryption_key = hmac.new(secret.encode(), b'gorilla-apple-token-encryption-v1', hashlib.sha256).digest()
        self.cipher = Fernet(base64.urlsafe_b64encode(encryption_key))
        self.http = request.build_opener(NoRedirect())

    @classmethod
    def configured(cls, secret):
        filename = os.getenv('COMMUNITY_APPLE_CONFIG', '')
        if not filename:
            candidate = Path(__file__).with_name('.apple') / 'config.json'
            if not candidate.exists():
                return None
            filename = str(candidate)
        path = Path(filename)
        config = json.loads(path.read_text())
        key = Path(config['privateKeyPath'])
        if not key.is_absolute():
            config['privateKeyPath'] = str(path.parent / key)
        if config.get('clientId') != 'com.gorilla.translation':
            raise ValueError('Apple clientId must match the native bundle ID')
        return cls(config, secret)

    def client_secret(self):
        now = int(time.time())
        return self.jwt.encode({'iss': self.team_id, 'iat': now, 'exp': now + 300,
                                'aud': self.issuer, 'sub': self.client_id},
                               self.private_key, algorithm='ES256', headers={'kid': self.key_id})

    def claims(self, token, nonce_hash):
        if not isinstance(token, str) or len(token) > 16384:
            raise ValueError('Invalid Apple token')
        key = self.keys.get_signing_key_from_jwt(token).key
        claims = self.jwt.decode(token, key, algorithms=['RS256'], audience=self.client_id,
                                 issuer=self.issuer, leeway=30,
                                 options={'require': ['iss', 'aud', 'exp', 'iat', 'sub', 'nonce']})
        if not isinstance(claims['sub'], str) or not 1 <= len(claims['sub']) <= 255:
            raise ValueError('Invalid Apple subject')
        if not isinstance(claims['nonce'], str) or not hmac.compare_digest(claims['nonce'], nonce_hash):
            raise ValueError('Apple nonce mismatch')
        if time.time() - claims['iat'] > 600:
            raise ValueError('Apple token too old')
        return claims

    def post(self, endpoint, fields):
        body = parse.urlencode(fields).encode()
        req = request.Request(self.issuer + endpoint, data=body,
                              headers={'Content-Type': 'application/x-www-form-urlencoded'})
        with self.http.open(req, timeout=10) as response:
            data = response.read(1024 * 1024 + 1)
            if len(data) > 1024 * 1024:
                raise ValueError('Apple response too large')
            return json.loads(data or b'{}')

    def exchange(self, identity_token, authorization_code, nonce_hash):
        if not isinstance(authorization_code, str) or not 1 <= len(authorization_code) <= 4096:
            raise ValueError('Invalid authorization code')
        initial = self.claims(identity_token, nonce_hash)
        result = self.post('/auth/token', {'grant_type': 'authorization_code', 'code': authorization_code,
                          'client_id': self.client_id, 'client_secret': self.client_secret()})
        verified = self.claims(result.get('id_token'), nonce_hash)
        if not hmac.compare_digest(initial['sub'], verified['sub']):
            raise ValueError('Apple subject mismatch')
        refresh = result.get('refresh_token')
        if not isinstance(refresh, str) or not 1 <= len(refresh) <= 8192:
            raise ValueError('Apple refresh token missing')
        return verified['sub'], refresh

    def encrypt(self, token):
        return self.cipher.encrypt(token.encode()).decode()

    def revoke_encrypted(self, encrypted):
        token = self.cipher.decrypt(encrypted.encode()).decode()
        self.post('/auth/revoke', {'client_id': self.client_id, 'client_secret': self.client_secret(),
                                 'token': token, 'token_type_hint': 'refresh_token'})
