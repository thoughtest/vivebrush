#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <download URL for the signed app ZIP>" >&2
    exit 1
fi
# Use the public GitHub release asset URL. Credentials must never be embedded.
python3 - "$1" <<'PY'
from pathlib import Path
import hashlib
import plistlib
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from email.utils import format_datetime
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

address = sys.argv[1]
url = urlsplit(address)
if not url.hostname or url.username is not None or url.password is not None or url.fragment or not (url.scheme == 'https' or (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost'))):
    raise SystemExit('Use an HTTPS download URL without embedded credentials (or localhost for tests).')
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
if not info.get('SUPublicEDKey'):
    raise SystemExit('No update key is configured. On your personal Mac, run scripts/setup-update-key.sh --personal-mac first.')
version = info['CFBundleShortVersionString']
directory = Path('dist') / version
archive = directory / f'ViveBrush-{version}-arm64.app.zip'
if not archive.is_file():
    raise SystemExit('No packaged app ZIP found. Run scripts/package.sh first.')
with zipfile.ZipFile(archive) as package:
    packaged_info = plistlib.loads(package.read('ViveBrush.app/Contents/Info.plist'))
for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'SUPublicEDKey',
            'SUFeedURL', 'LSMinimumSystemVersion', 'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction'):
    if packaged_info.get(key) != info.get(key):
        raise SystemExit(f'The packaged app has a different {key}. Run scripts/package.sh again before signing.')
if url.path.rsplit('/', 1)[-1] != archive.name:
    raise SystemExit(f'The download URL must end with {archive.name}.')
if not (directory / f'ViveBrush-{version}-arm64.dmg').is_file():
    raise SystemExit('No packaged DMG found. Run scripts/package.sh first.')
tools = Path('.build/artifacts/sparkle/Sparkle/bin')
account = 'com.vivebrush.app.updates'
public_key = subprocess.check_output([str(tools / 'generate_keys'), '--account', account, '-p'], text=True).strip()
if public_key != info['SUPublicEDKey']:
    raise SystemExit('The Keychain signing key does not match SUPublicEDKey. Import the original signing key first.')
signature = subprocess.check_output([str(tools / 'sign_update'), '--account', account, '-p', str(archive)], text=True).strip()
subprocess.run([str(tools / 'sign_update'), '--account', account, '--verify', str(archive), signature], check=True)
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', sparkle)
root = ET.Element('rss', version='2.0')
channel = ET.SubElement(root, 'channel')
ET.SubElement(channel, 'title').text = 'ViveBrush Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'ViveBrush {version}'
ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc), usegmt=True)
minimum = info['LSMinimumSystemVersion'].split('.')
ET.SubElement(item, f'{{{sparkle}}}minimumSystemVersion').text = '.'.join(minimum + ['0'] * (3 - len(minimum)))
ET.SubElement(item, f'{{{sparkle}}}hardwareRequirements').text = 'arm64'
ET.SubElement(item, f'{{{sparkle}}}version').text = info['CFBundleVersion']
ET.SubElement(item, f'{{{sparkle}}}shortVersionString').text = version
ET.SubElement(item, 'description').text = '서명된 앱 내 업데이트 확인·설치·재시작, 수동 색 선택과 자동 색상 옵션을 제공합니다.'
ET.SubElement(item, 'enclosure', {
    'url': address, 'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    f'{{{sparkle}}}edSignature': signature,
})
feed = directory / 'appcast.xml'
ET.indent(root)
ET.ElementTree(root).write(feed, encoding='utf-8', xml_declaration=True)
subprocess.run([str(tools / 'sign_update'), '--account', account, str(feed)], check=True)
subprocess.run([str(tools / 'sign_update'), '--account', account, '--verify', str(feed)], check=True)
files = [directory / f'ViveBrush-{version}-arm64.dmg', archive, feed]
(directory / 'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in files))
print(f'Signed update feed: {feed}')
PY
