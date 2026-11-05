"""Serve one explicitly configured, signed Android APK; no directory listing."""
import hashlib
import os
from pathlib import Path


class AndroidRelease:
    def __init__(self, path, version_code, version_name):
        self.path = Path(path)
        self.version_code = int(version_code)
        self.version_name = str(version_name)[:60]
        if self.version_code < 1:
            raise ValueError('Invalid Android version code')
        self.cached = None

    @classmethod
    def configured(cls):
        path = os.getenv('COMMUNITY_ANDROID_APK_PATH', '')
        return cls(path, os.environ['COMMUNITY_ANDROID_VERSION_CODE'],
                   os.environ['COMMUNITY_ANDROID_VERSION_NAME']) if path else None

    def manifest(self):
        stat = self.path.stat()
        if not self.path.is_file() or not 0 < stat.st_size <= 200 * 1024 * 1024:
            raise ValueError('Invalid Android APK file')
        stamp = (stat.st_size, stat.st_mtime_ns)
        if not self.cached or self.cached[0] != stamp:
            with self.path.open('rb') as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            self.cached = (stamp, digest)
        return {'available': True, 'versionCode': self.version_code,
                'versionName': self.version_name, 'bytes': stat.st_size,
                'sha256': self.cached[1]}
