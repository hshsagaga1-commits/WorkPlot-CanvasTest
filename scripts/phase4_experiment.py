#!/usr/bin/env python3
"""Analyze the supported preset experiment with before, changed and restored evidence."""
import argparse
import json
from pathlib import Path
from phase3_compare import EvidenceError, compare_reports, inspect_png, read_report

PHASES = ('before', 'changed', 'restored')
SURFACES = ('home', 'settings', 'app')


def plan():
    return {'format':'resolutionlab.preset-experiment','schema':1,
            'presetOriginal':None,'presetChanged':None,
            'captures':dict.fromkeys(PHASES),
            'screenshots':{surface:dict.fromkeys(PHASES) for surface in SURFACES}}


def analyze(path):
    manifest,_ = read_report(path)
    if (manifest.get('format') != 'resolutionlab.preset-experiment'
            or type(manifest.get('schema')) is not int or manifest['schema'] != 1):
        raise EvidenceError('Manifesto de experimento incompatível.')
    captures=manifest.get('captures')
    images=manifest.get('screenshots')
    if not isinstance(captures,dict) or not isinstance(images,dict):
        raise EvidenceError('O manifesto precisa de captures e screenshots.')
    missing=[phase for phase in PHASES if not captures.get(phase)]
    result={'schema':1,'globalCanvasEvidence':'unverified','missingCaptures':missing,
            'presetOriginal':manifest.get('presetOriginal'), 'presetChanged':manifest.get('presetChanged')}
    if missing:
        result['executionStatus']='awaiting_device'
        return result
    def selected(value):
        if not isinstance(value,str) or not value.strip():
            raise EvidenceError('Nome de arquivo inválido no manifesto.')
        target=(path.parent/value).resolve()
        if not target.is_relative_to(path.parent.resolve()):
            raise EvidenceError('Mantenha os arquivos de evidência junto ao manifesto.')
        return target
    reports={};files={}
    for phase in PHASES:
        reports[phase],files[phase]=read_report(selected(captures[phase]))
    change=compare_reports(reports['before'],reports['changed'])
    restoration=compare_reports(reports['before'],reports['restored'])
    compare_reports(reports['changed'],reports['restored'])
    states={item['comparison'] for item in restoration['geometry'].values()}
    # Older reports may omit window fields. Missing fields remain explicit in the output.
    essential=('bounds','nativeBounds','currentMode','availableModes','scale','nativeScale')
    values=[restoration['geometry'][key]['comparison'] for key in essential]
    recovery='different' if 'different' in states else (
        'indeterminate' if 'unavailable' in values else 'returned_within_measured_fields')
    snapshots={};missing_images=[]
    for surface in SURFACES:
        mapping=images.get(surface)
        if not isinstance(mapping,dict):raise EvidenceError('Grupo de capturas inválido.')
        snapshots[surface]={}
        for phase in PHASES:
            value=mapping.get(phase)
            if not value:missing_images.append(f'{surface}/{phase}');continue
            snapshots[surface][phase]=inspect_png(selected(value))
    result.update({'executionStatus':'awaiting_external_captures' if missing_images else 'measured_pending_visual_review',
                   'change':change,'restoration':restoration,'restorationGeometry':recovery,
                   'screenshots':snapshots,'missingScreenshots':missing_images,'reportFiles':files,
                   'imageProvenance':'operator_named','visualReview':'pending'})
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest',type=Path,nargs='?')
    args=parser.parse_args()
    try:result=analyze(args.manifest) if args.manifest else plan()
    except (EvidenceError,OSError) as error:parser.exit(2,f'{error}\n')
    print(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False))

if __name__=='__main__':main()
