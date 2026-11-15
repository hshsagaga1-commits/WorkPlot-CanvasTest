#!/usr/bin/env python3
"""Reconstitute the approved project from pinned source and exact overlays."""
from pathlib import Path
import argparse, hashlib, shutil, subprocess, json
parser=argparse.ArgumentParser()
parser.add_argument('upstream',type=Path)
parser.add_argument('zipfoundation',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
here=Path(__file__).resolve().parent
for path, expected in [(args.upstream,'9756071f3cfa7a8902dbf1a4ee81beebc1210d0a'),
                       (args.zipfoundation,'22787ffb59de99e5dc1fbfe80b19c97a904ad48d')]:
    actual=subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    if actual != expected: raise SystemExit(f'Wrong source commit: {actual}')
if args.output.exists(): raise SystemExit('Output must not already exist')
args.output.mkdir(parents=True)
for name in ['WorkPlot','Support']:
    shutil.copytree(args.upstream/name,args.output/name)
shutil.copy2(args.upstream/'LICENSE',args.output/'LICENSE')
for name in ['Package.swift','LICENSE','Sources','Tests']:
    source=args.zipfoundation/name;target=args.output/'Vendor/ZIPFoundation'/name
    target.parent.mkdir(parents=True,exist_ok=True)
    if source.is_dir(): shutil.copytree(source,target)
    else: shutil.copy2(source,target)
shutil.copytree(here/'overlay',args.output,dirs_exist_ok=True)
adjustment=json.loads((here/"build-script-adjustment.json").read_text())
checked=0
for line in (here/'APPROVED_SHA256SUMS.txt').read_text().splitlines():
    digest,name=line.split('  ',1)
    if name.startswith(('WorkPlot/','Support/','Vendor/','scripts/','evidence/original-')):
        if name == adjustment['path']:
            if digest != adjustment['originalSHA256']: raise SystemExit('Original build-script hash mismatch')
            digest=adjustment['buildSHA256']
        actual=hashlib.sha256((args.output/name).read_bytes()).hexdigest()
        if actual!=digest: raise SystemExit(f'Approved project mismatch: {name}')
        checked+=1
print(f'File hashes verified: {checked}; only build script has the documented packaging adjustment.',flush=True)
subprocess.run(['python3',str(args.output/'scripts/verify-source.py')],check=True)
