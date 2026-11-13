"""Reject stale or unsafe release inputs before any signing-key access."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile


class AppcastChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='vivebrush-appcast-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'Resources').mkdir()
        self.script = self.root / 'scripts/create-appcast.sh'
        shutil.copyfile(Path(__file__).resolve().parents[1] / 'scripts/create-appcast.sh', self.script)
        self.info = dict(CFBundleIdentifier='com.vivebrush.app', CFBundleShortVersionString='0.2.0',
                         CFBundleVersion='4', SUPublicEDKey='A' * 43 + '=',
                         SUFeedURL='https://example.com/appcast.xml', LSMinimumSystemVersion='14.0',
                         SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)
        (self.root / 'Resources/Info.plist').write_bytes(plistlib.dumps(self.info))
        self.directory = self.root / 'dist/0.2.0'
        self.directory.mkdir(parents=True)
        self.archive = self.directory / 'ViveBrush-0.2.0-arm64.app.zip'
        self.url = 'https://example.com/' + self.archive.name
        (self.directory / 'ViveBrush-0.2.0-arm64.dmg').touch()
        self.package(self.info)

    def package(self, info):
        with zipfile.ZipFile(self.archive, 'w') as package:
            package.writestr('ViveBrush.app/Contents/Info.plist', plistlib.dumps(info))

    def reject(self, expected, url=None):
        result = subprocess.run(['bash', str(self.script), url or self.url], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected, result.stderr + result.stdout)
        self.assertFalse((self.directory / 'appcast.xml').exists())

    def test_stale_build_key_and_feed(self):
        for field in ('CFBundleVersion', 'SUPublicEDKey', 'SUFeedURL'):
            with self.subTest(field=field):
                self.package(dict(self.info, **{field: 'stale'}))
                self.reject(f'different {field}')

    def test_missing_package(self):
        self.archive.unlink()
        self.reject('No packaged app ZIP')

    def test_unsafe_urls(self):
        for url in ('http://example.com/app.zip', 'https:///app.zip',
                    'https://token@example.com/app.zip', 'https://@example.com/app.zip',
                    self.url + '#fragment'):
            with self.subTest(url=url):
                self.reject('Use an HTTPS download URL', url)

    def test_wrong_filename(self):
        self.reject('download URL must end with', 'https://example.com/other.zip')

    def test_missing_dmg(self):
        (self.directory / 'ViveBrush-0.2.0-arm64.dmg').unlink()
        self.reject('No packaged DMG')


if __name__ == '__main__':
    unittest.main()
