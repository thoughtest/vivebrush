"""Reject stale or unsafe release inputs before any signing-key access."""
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile


MULTI_VERSION_NOTES = """# ViveBrush 0.2.1

- Fix toolbar safe area for notch displays
- Exit annotation on focus or Space change

Apple Silicon only.

# ViveBrush 0.2.0

- Signed in-app updates via Sparkle
- Manual color picker and optional rotation
"""


class AppcastChecks(unittest.TestCase):
    def setUp(self):
        self.repo_root = Path(__file__).resolve().parents[1]
        self.temporary = tempfile.TemporaryDirectory(prefix='vivebrush-appcast-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'Resources').mkdir()
        self.script = self.root / 'scripts/create-appcast.sh'
        shutil.copyfile(self.repo_root / 'scripts/create-appcast.sh', self.script)
        shutil.copyfile(self.repo_root / 'scripts/verify-signature.swift', self.root / 'scripts/verify-signature.swift')
        (self.root / 'RELEASE_NOTES.md').write_text(MULTI_VERSION_NOTES, encoding='utf-8')
        self.set_version('0.2.0', '4')

    def set_version(self, version, build):
        self.version = version
        self.info = dict(
            CFBundleIdentifier='com.vivebrush.app',
            CFBundleShortVersionString=version,
            CFBundleVersion=build,
            CFBundleIconFile='AppIcon',
            SUPublicEDKey='A' * 43 + '=',
            SUFeedURL='https://example.com/appcast.xml',
            LSMinimumSystemVersion='14.0',
            SURequireSignedFeed=True,
            SUVerifyUpdateBeforeExtraction=True,
        )
        (self.root / 'Resources/Info.plist').write_bytes(plistlib.dumps(self.info))
        self.directory = self.root / 'dist' / version
        self.directory.mkdir(parents=True, exist_ok=True)
        self.archive = self.directory / f'ViveBrush-{version}-arm64.app.zip'
        self.dmg = self.directory / f'ViveBrush-{version}-arm64.dmg'
        self.url = 'https://example.com/' + self.archive.name
        self.dmg.write_bytes(b'dummy dmg')
        self.package(self.info)

    def package(self, info):
        with zipfile.ZipFile(self.archive, 'w') as package:
            package.writestr('ViveBrush.app/Contents/Info.plist', plistlib.dumps(info))

    def run_script(self, *args, env=None):
        merged_env = os.environ.copy()
        for key in ('SPARKLE_ED_KEY_FILE', 'SPARKLE_PRIVATE_KEY', 'VIVEBRUSH_RELEASE_NOTES'):
            merged_env.pop(key, None)
        if env:
            merged_env.update(env)
        return subprocess.run(
            ['bash', str(self.script), *args],
            capture_output=True,
            text=True,
            env=merged_env,
        )

    def reject(self, expected, url=None, extra_args=(), env=None):
        result = self.run_script(*extra_args, url or self.url, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected, result.stderr + result.stdout)
        self.assertFalse((self.directory / 'appcast.xml').exists())

    def test_stale_build_key_and_feed(self):
        for field in ('CFBundleVersion', 'CFBundleIconFile', 'SUPublicEDKey', 'SUFeedURL'):
            with self.subTest(field=field):
                self.package(dict(self.info, **{field: 'stale'}))
                self.reject(f'different {field}')

    def test_missing_package(self):
        self.archive.unlink()
        self.reject('No packaged app ZIP')

    def test_unsafe_urls(self):
        for url in (
            'http://example.com/app.zip',
            'https:///app.zip',
            'https://token@example.com/app.zip',
            'https://@example.com/app.zip',
            self.url + '#fragment',
        ):
            with self.subTest(url=url):
                self.reject('Use an HTTPS download URL', url)

    def test_wrong_filename(self):
        self.reject('download URL must end with', 'https://example.com/other.zip')

    def test_missing_dmg(self):
        self.dmg.unlink()
        self.reject('No packaged DMG')

    def test_extracts_matching_version_notes_only(self):
        self.set_version('0.2.1', '5')
        res_021 = self.run_script('--print-notes')
        self.assertEqual(res_021.returncode, 0, res_021.stderr)
        self.assertIn('Fix toolbar safe area for notch displays', res_021.stdout)
        self.assertIn('Exit annotation on focus or Space change', res_021.stdout)
        self.assertNotIn('Signed in-app updates via Sparkle', res_021.stdout)
        self.assertNotIn('Apple Silicon only.', res_021.stdout)

        self.set_version('0.2.0', '4')
        res_020 = self.run_script('--print-notes')
        self.assertEqual(res_020.returncode, 0, res_020.stderr)
        self.assertIn('Signed in-app updates via Sparkle', res_020.stdout)
        self.assertIn('Manual color picker and optional rotation', res_020.stdout)
        self.assertNotIn('Fix toolbar safe area', res_020.stdout)

    def test_notes_overrides(self):
        self.set_version('0.9.9', '99')
        env_res = self.run_script('--print-notes', env={'VIVEBRUSH_RELEASE_NOTES': 'Env override note'})
        self.assertEqual(env_res.returncode, 0, env_res.stderr)
        self.assertEqual(env_res.stdout.strip(), 'Env override note')

        cli_res = self.run_script(
            '--notes', 'CLI override note', '--print-notes',
            env={'VIVEBRUSH_RELEASE_NOTES': 'Env override note'},
        )
        self.assertEqual(cli_res.returncode, 0, cli_res.stderr)
        self.assertEqual(cli_res.stdout.strip(), 'CLI override note')

        self.reject('--notes must not be empty', extra_args=('--notes', '   '))

    def test_missing_or_empty_release_notes(self):
        (self.root / 'RELEASE_NOTES.md').unlink()
        self.reject('Missing RELEASE_NOTES.md')

        (self.root / 'RELEASE_NOTES.md').write_text(MULTI_VERSION_NOTES, encoding='utf-8')
        self.set_version('0.9.9', '99')
        self.reject("missing section '# ViveBrush 0.9.9'")

        (self.root / 'RELEASE_NOTES.md').write_text('# ViveBrush 0.2.10\n\n- Other release\n', encoding='utf-8')
        self.set_version('0.2.1', '5')
        self.reject("missing section '# ViveBrush 0.2.1'")

        (self.root / 'RELEASE_NOTES.md').write_text('# ViveBrush 0.2.1\n\nNo bullets here.\n', encoding='utf-8')
        self.reject('has no release note bullets')

    def test_missing_sparkle_ed_key_file(self):
        self.reject('Signing key file is missing or empty', env={'SPARKLE_ED_KEY_FILE': str(self.root / 'nope.key')})

    def test_headless_signing_writes_version_description_and_cleans_temp_key(self):
        tools = self.root / '.build/artifacts/sparkle/Sparkle/bin'
        tools.mkdir(parents=True)
        invocations = self.root / 'sign_update_calls.log'
        sign_update = tools / 'sign_update'
        sign_update.write_text(
            f"""#!/usr/bin/env python3
from pathlib import Path
import stat
import sys

args = sys.argv[1:]
Path({str(invocations)!r}).open('a').write(' '.join(args) + '\\n')
assert '--account' not in args, f'Unexpected Keychain --account in headless mode: {{args}}'
assert '--ed-key-file' in args, f'Missing --ed-key-file: {{args}}'
key_path = Path(args[args.index('--ed-key-file') + 1])
mode = stat.S_IMODE(key_path.stat().st_mode)
assert mode == 0o600, f'Expected 0600 permissions, got {{oct(mode)}}'
assert key_path.read_text().strip() == 'TEST_PRIVATE_KEY_VALUE'
if '-p' in args:
    print('B' * 86 + '==')
else:
    feed = Path(args[-1])
    content = feed.read_bytes()
    trailer = f'<!-- sparkle-signatures:\\nedSignature: {{"C" * 86}}==\\nlength: {{len(content)}}\\n-->'.encode()
    feed.write_bytes(content + trailer)
""",
            encoding='utf-8',
        )
        sign_update.chmod(0o755)

        fake_bin = self.root / 'fake-bin'
        fake_bin.mkdir()
        fake_swiftc = fake_bin / 'swiftc'
        fake_swiftc.write_text(
            """#!/usr/bin/env python3
from pathlib import Path
import sys
out = Path(sys.argv[sys.argv.index('-o') + 1])
out.write_text('#!/bin/sh\\nexit 0\\n')
out.chmod(0o755)
""",
            encoding='utf-8',
        )
        fake_swiftc.chmod(0o755)

        isolated_tmp = self.root / 'tmp'
        isolated_tmp.mkdir()

        for version, build, expected, excluded in (
            ('0.2.1', '5', 'Fix toolbar safe area for notch displays', 'Signed in-app updates via Sparkle'),
            ('0.2.0', '4', 'Signed in-app updates via Sparkle', 'Fix toolbar safe area for notch displays'),
        ):
            with self.subTest(version=version):
                invocations.unlink(missing_ok=True)
                self.set_version(version, build)
                res = self.run_script(
                    self.url,
                    env={
                        'PATH': f'{fake_bin}:{os.environ.get("PATH", "")}',
                        'TMPDIR': str(isolated_tmp),
                        'SPARKLE_PRIVATE_KEY': '  TEST_PRIVATE_KEY_VALUE  \n',
                    },
                )
                self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
                self.assertEqual(list(isolated_tmp.iterdir()), [], 'Temporary key file leaked after exit')
                calls = invocations.read_text().splitlines()
                self.assertEqual(len(calls), 2)
                feed = self.directory / 'appcast.xml'
                raw = feed.read_bytes()
                content, marker, _ = raw.rpartition(b'<!-- sparkle-signatures:\n')
                self.assertTrue(marker)
                root = ET.fromstring(content)
                description = root.findtext('./channel/item/description')
                self.assertIn(expected, description)
                self.assertNotIn(excluded, description)
                sums = (self.directory / 'SHA256SUMS.txt').read_text().splitlines()
                self.assertEqual(len(sums), 3)

    def test_headless_failed_feed_verification_removes_appcast_and_key(self):
        tools = self.root / '.build/artifacts/sparkle/Sparkle/bin'
        tools.mkdir(parents=True, exist_ok=True)
        sign_update = tools / 'sign_update'
        sign_update.write_text(
            """#!/usr/bin/env python3
import sys
if '-p' in sys.argv[1:]:
    print('B' * 86 + '==')
# Deliberately skip appending <!-- sparkle-signatures: --> when signing the feed.
""",
            encoding='utf-8',
        )
        sign_update.chmod(0o755)
        fake_bin = self.root / 'fake-bin-fail'
        fake_bin.mkdir(exist_ok=True)
        fake_swiftc = fake_bin / 'swiftc'
        fake_swiftc.write_text(
            """#!/usr/bin/env python3
from pathlib import Path
import sys
out = Path(sys.argv[sys.argv.index('-o') + 1])
out.write_text('#!/bin/sh\\nexit 0\\n')
out.chmod(0o755)
""",
            encoding='utf-8',
        )
        fake_swiftc.chmod(0o755)
        isolated_tmp = self.root / 'tmp-fail'
        isolated_tmp.mkdir(exist_ok=True)
        self.set_version('0.2.1', '5')
        self.reject(
            'missing embedded sparkle-signatures',
            env={
                'PATH': f'{fake_bin}:{os.environ.get("PATH", "")}',
                'TMPDIR': str(isolated_tmp),
                'SPARKLE_PRIVATE_KEY': 'TEST_PRIVATE_KEY_VALUE',
            },
        )
        self.assertEqual(list(isolated_tmp.iterdir()), [], 'Temporary key file leaked after failure')
        self.assertFalse((self.directory / 'SHA256SUMS.txt').exists())

    def test_repository_release_notes_match_info_plist(self):
        clean_env = os.environ.copy()
        clean_env.pop('VIVEBRUSH_RELEASE_NOTES', None)
        result = subprocess.run(
            ['bash', str(self.repo_root / 'scripts/create-appcast.sh'), '--print-notes'],
            cwd=self.repo_root,
            capture_output=True,
            text=True,
            env=clean_env,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
