#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
python3 - "${1:-}" <<'PY'
from pathlib import Path
import base64
import hashlib
import plistlib
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile

def require(condition, message):
    if not condition:
        raise SystemExit(message)

info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
directory = Path(sys.argv[1] or f'dist/{version}')
archive = directory / f'ViveBrush-{version}-arm64.app.zip'
feed = directory / 'appcast.xml'
names = {archive.name, f'ViveBrush-{version}-arm64.dmg', feed.name}
lines = (directory / 'SHA256SUMS.txt').read_text().splitlines()
require(len(lines) == 3, 'Expected checksums for exactly the DMG, app ZIP, and signed feed.')
checked = set()
for line in lines:
    digest, name = line.split('  ', 1)
    require(name in names and name not in checked, 'Unexpected or duplicate checksum entry.')
    require(hashlib.sha256((directory / name).read_bytes()).hexdigest() == digest, f'Checksum mismatch: {name}')
    checked.add(name)

with zipfile.ZipFile(archive) as package:
    require(len(package.namelist()) == len(set(package.namelist())), 'Duplicate entries in app ZIP.')
    packaged = plistlib.loads(package.read('ViveBrush.app/Contents/Info.plist'))
for key in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'SUPublicEDKey',
            'SUFeedURL', 'LSMinimumSystemVersion', 'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction'):
    require(packaged.get(key) == info.get(key), f'Packaged metadata mismatch: {key}')
require(packaged.get('SURequireSignedFeed') is True and packaged.get('SUVerifyUpdateBeforeExtraction') is True,
        'Signed feed and archive validation must be enabled.')
public_key = packaged['SUPublicEDKey']
require(len(base64.b64decode(public_key, validate=True)) == 32, 'Invalid update public key.')

data = feed.read_bytes()
content, marker, block = data.rpartition(b'<!-- sparkle-signatures:\n')
require(bool(marker) and b'-->' in block, 'Missing embedded feed signature.')
fields = dict(line.split(':', 1) for line in block.split(b'-->', 1)[0].decode().splitlines() if ':' in line)
require(int(fields.get('length', '-1')) == len(content), 'Signed feed length mismatch.')
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
root = ET.fromstring(content)
items = root.findall('./channel/item')
require(len(items) == 1, 'Expected exactly one release item.')
item = items[0]
require(item.findtext(sparkle + 'version') == packaged['CFBundleVersion'], 'Feed build number mismatch.')
require(item.findtext(sparkle + 'shortVersionString') == version, 'Feed display version mismatch.')
require(item.findtext(sparkle + 'hardwareRequirements') == 'arm64', 'Feed must target Apple Silicon.')
enclosure = item.find('enclosure')
require(enclosure is not None, 'Missing update enclosure.')
url = urlsplit(enclosure.attrib['url'])
require(url.hostname and url.username is None and url.password is None and not url.fragment and
        (url.scheme == 'https' or (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost'))),
        'Invalid download URL.')
require(url.path.rsplit('/', 1)[-1] == archive.name, 'Download URL filename mismatch.')
require(int(enclosure.attrib['length']) == archive.stat().st_size, 'Archive length mismatch.')

with tempfile.TemporaryDirectory(prefix='vivebrush-verify-') as temporary:
    temporary = Path(temporary)
    verifier = temporary / 'verify-signature'
    subprocess.run(['swiftc', 'scripts/verify-signature.swift', '-o', str(verifier)], check=True)
    signed_content = temporary / 'feed-content.xml'
    signed_content.write_bytes(content)
    subprocess.run([str(verifier), public_key, str(signed_content), fields['edSignature'].strip()], check=True)
    subprocess.run([str(verifier), public_key, str(archive), enclosure.attrib[sparkle + 'edSignature']], check=True)
    subprocess.run(['ditto', '-x', '-k', str(archive), str(temporary)], check=True)
    app = temporary / 'ViveBrush.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    architecture = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/ViveBrush')], text=True).strip()
    require(architecture == 'arm64', 'Expected an arm64-only executable.')
print(f'PASS: ViveBrush {version} ({packaged["CFBundleVersion"]}) — checksums, public-key feed/ZIP signatures, bundle signature, arm64')
PY
