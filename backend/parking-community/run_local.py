"""Local Gmail-backed runner; secrets never appear in command arguments or logs."""
import argparse
import json
import os
from pathlib import Path
import runpy
import secrets
import sys
import time

ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG = ROOT / '.env.local.json'


def initialise(path):
    if path.exists():
        return
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump({'gmailAddress': '', 'gmailAppPassword': '',
                   'serverSecret': secrets.token_urlsafe(48)}, output, indent=2)
        output.write('\n')


def load_settings(path):
    settings = json.loads(path.read_text())
    email = settings.get('gmailAddress', '').strip()
    password = ''.join(settings.get('gmailAppPassword', '').split())
    secret = settings.get('serverSecret', '')
    if not email or '@' not in email or len(password) != 16 or len(secret) < 32:
        raise ValueError('Fill in gmailAddress and the 16-character Gmail app password')
    return {'COMMUNITY_SMTP_HOST': 'smtp.gmail.com', 'COMMUNITY_SMTP_PORT': '587',
            'COMMUNITY_SMTP_USER': email, 'COMMUNITY_MAIL_FROM': email,
            'COMMUNITY_SMTP_PASSWORD': password, 'COMMUNITY_SECRET': secret}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    parser.add_argument('--init', action='store_true')
    parser.add_argument('--wait-for-config', action='store_true')
    parser.add_argument('--check-smtp', action='store_true')
    args = parser.parse_args()
    initialise(args.config)
    if args.init:
        print('Local configuration created; fill only gmailAddress and gmailAppPassword.')
        return
    while True:
        try:
            settings = load_settings(args.config)
            os.chmod(args.config, 0o600)
            break
        except (ValueError, TypeError, AttributeError):
            if not args.wait_for_config:
                parser.error('Complete the local Gmail configuration first. Never paste credentials into chat.')
            print('Waiting for local Gmail configuration...', flush=True)
            time.sleep(5)
    os.environ.update(settings)
    push_config = ROOT / '.push' / 'config.json'
    if push_config.exists():
        os.environ.setdefault('COMMUNITY_PUSH_CONFIG', str(push_config))
    if args.check_smtp:
        import smtplib
        import ssl
        try:
            with smtplib.SMTP(settings['COMMUNITY_SMTP_HOST'], 587, timeout=15) as smtp:
                smtp.starttls(context=ssl.create_default_context())
                smtp.login(settings['COMMUNITY_SMTP_USER'], settings['COMMUNITY_SMTP_PASSWORD'])
            print('Gmail authentication succeeded. No email was sent.')
        except smtplib.SMTPAuthenticationError as error:
            print(f'Gmail rejected authentication (SMTP {error.smtp_code}); check the account/app-password pairing. No credentials logged.')
            sys.exit(1)
        except Exception as error:
            print(f'Gmail connection did not complete ({type(error).__name__}); authentication is unconfirmed. No credentials logged.')
            sys.exit(1)
        return
    print('Starting local parking-community service on 127.0.0.1:8787', flush=True)
    sys.argv = [str(ROOT / 'service.py'), '--db', str(ROOT / 'community.sqlite3')]
    runpy.run_path(str(ROOT / 'service.py'), run_name='__main__')


if __name__ == '__main__':
    main()
