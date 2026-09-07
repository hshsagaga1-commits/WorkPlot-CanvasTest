#!/usr/bin/env python3
"""Verify source preservation and packaging, without claiming an Xcode compilation."""
from pathlib import Path
import hashlib, json, plistlib, re, xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
evidence = json.loads((root/'evidence/original-access-sha256.json').read_text())
project_path = 'WorkPlot/WorkPlot.xcodeproj/project.pbxproj'
for name, expected in evidence['protectedFiles'].items():
    if name == project_path:
        continue  # Dependency reference changed; its full diff is supplied.
    actual = hashlib.sha256((root/name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f'FAIL original-source hash: {name}')
project = (root/project_path).read_text()
identities = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);', project)
assert len(identities) == 2 and set(identities) == {'com.apple.mobile.MobileHouseArrest'}, identities
assert 'repositoryURL' not in project
assert 'relativePath = "../Vendor/ZIPFoundation";' in project
assert (root/'Vendor/ZIPFoundation/Package.swift').is_file()
scheme = ET.parse(root/'WorkPlot/WorkPlot.xcodeproj/xcshareddata/xcschemes/WorkPlot.xcscheme')
for ref in scheme.iter('BuildableReference'):
    assert ref.attrib['BlueprintIdentifier'] == 'AA0000000000000000000100'
    assert ref.attrib['BuildableName'] == 'WorkPlot.app'
    assert ref.attrib['BlueprintIdentifier'] in project
with (root/'Support/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
assert info['CFBundleIdentifier'] == '$(PRODUCT_BUNDLE_IDENTIFIER)'
assert (root/'WorkPlot/UI/CanvasInvestigationView.swift').is_file()
print('PASS: original access/startup/plist hashes; unchanged bundle ID; shared scheme; local dependency.')
print('This check does not compile Swift or validate behavior on an iPhone.')
