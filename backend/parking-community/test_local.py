import json
from pathlib import Path
import tempfile
import unittest
from run_local import initialise, load_settings

class LocalConfigTests(unittest.TestCase):
    def test_secret_is_private_and_reinitialisation_preserves_it(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'settings.json'
            initialise(path)
            original = path.read_bytes()
            self.assertEqual(0o600, path.stat().st_mode & 0o777)
            initialise(path)
            self.assertEqual(original, path.read_bytes())
            with self.assertRaises(ValueError):
                load_settings(path)

    def test_grouped_password_and_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'settings.json'
            path.write_text(json.dumps({'gmailAddress': ' test@gmail.com ', 'gmailAppPassword': 'abcd efgh ijkl mnop', 'serverSecret': 'x'*48}))
            settings = load_settings(path)
            self.assertEqual('abcdefghijklmnop', settings['COMMUNITY_SMTP_PASSWORD'])
            self.assertEqual('test@gmail.com', settings['COMMUNITY_MAIL_FROM'])
            self.assertEqual('587', settings['COMMUNITY_SMTP_PORT'])

if __name__ == '__main__':
    unittest.main()
