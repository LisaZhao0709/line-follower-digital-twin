"""Static dependency/model source checks, explicitly not a MATLAB startup test."""
from pathlib import Path
import json
import re
import zipfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]

def main():
    names=set(p.stem for p in ROOT.glob('*.m'));scripts={'START_PROJECT','OPEN_MODEL'}
    for file in ROOT.glob('*.m'):
        first=file.read_text(encoding='utf-8-sig').splitlines()[0]
        if file.stem not in scripts:
            match=re.search(r'function\s+(?:\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?(\w+)\s*\(',first)
            assert match and match.group(1)==file.stem,(file.name,first)
    with zipfile.ZipFile(ROOT/'models'/'LineFollowerTwin.slx') as archive:
        assert archive.testzip() is None
        functions=[];blocks=[]
        for name in archive.namelist():
            if name.endswith('.xml'):
                tree=ET.fromstring(archive.read(name));functions.extend(n.text for n in tree.iter('P') if n.attrib.get('Name')=='script')
                blocks.extend(tree.iter('Block'))
        for file in (ROOT/'kernels').glob('*.m'):
            content=file.read_text(encoding='utf-8-sig').replace('\r\n','\n').strip()
            assert any(s and s.replace('\r\n','\n').strip()==content for s in functions),f'Embedded kernel differs from source: {file.name}'
        for name in ['LeftEnable','RightEnable']:
            assert any(b.attrib.get('Name')==name and b.attrib.get('BlockType')=='Switch' for b in blocks)
        assert any(b.attrib.get('Name')=='PIDController' for b in blocks)
    start=(ROOT/'START_PROJECT.m').read_text(encoding='utf-8')
    assert all(n in start for n in ['addpath','build_twin','twin_app'])
    assert {'build_twin','twin_app','twin_config','RUN_ALL_WEEKS','week5_validate','week6_validate','week7_validate','week8_validate'}<=names
    latest=(ROOT/'results'/'week8_latest.txt').read_text().strip().replace('\\','/').rsplit('/',1)[-1]
    runtime_file=ROOT/'results'/latest/'startup_runtime_checks.json'
    runtime=json.loads(runtime_file.read_text(encoding='utf-8')) if runtime_file.exists() else {}
    runtime_passed=bool(runtime.get('passed'))
    result=dict(passed=True,matlab_source_files=len(names),embedded_kernels_match=6,slx_crc_verified=True,
      startup_dependencies_present=True,startup_runtime_passed=runtime_passed,
      additional_matlab_restart_check='Passed: independent MATLAB startup, START_PROJECT, UI open/step/reset/close.' if runtime_passed else 'Not yet executed; static inspection does not substitute for MATLAB startup.',
      startup_runtime_checked_at=runtime.get('checked_at'))
    (ROOT/'results'/latest/'delivery_source_checks.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('DELIVERY_STATIC_SOURCE_CHECKS_PASSED')

if __name__=='__main__':main()
