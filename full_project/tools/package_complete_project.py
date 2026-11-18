"""Freeze sources, validate evidence checksums, and build the portable eight-week bundle."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import zipfile
import io
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]

def latest(week):
    name=(ROOT/'results'/f'week{week}_latest.txt').read_text().strip().replace('\\','/').rsplit('/',1)[-1]
    return ROOT/'results'/name

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    from check_delivery_sources import main as check_sources
    check_sources()
    directory=latest(8)
    status=json.loads((directory/'status.json').read_text());assert status['passed'] and not status['independent_review_pending']
    for week in [5,6,7]:assert json.loads((latest(week)/'status.json').read_text())['passed']
    snapshot=directory/'source_snapshot';snapshot.mkdir(exist_ok=True)
    for file in ROOT.iterdir():
        if file.is_file() and file.suffix in ('.m','.md'):shutil.copy2(file,snapshot/file.name)
    for folder in ['data','kernels','tools','models','docs']:
        source=ROOT/folder
        if not source.exists():continue
        for file in source.rglob('*'):
            if file.is_file() and 'backups' not in file.parts and '__pycache__' not in file.parts:
                dest=snapshot/file.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
    files=[]
    for week in [5,6,7,8]:
        for file in latest(week).rglob('*'):
            if file.is_file() and file.name not in ['file_manifest.csv','delivery_status.json']:
                files.append(dict(relative_path=file.relative_to(ROOT).as_posix(),bytes=file.stat().st_size,sha256=digest(file)))
    manifest=directory/'file_manifest.csv';pd.DataFrame(files).to_csv(manifest,index=False)
    for row in files:assert digest(ROOT/row['relative_path'])==row['sha256']
    target=ROOT.parent/'循迹小车_完整八周工程.zip'
    selected=set()
    for file in ROOT.iterdir():
        if file.is_file() and file.suffix in ('.m','.md'):selected.add(file)
    for folder in ['data','kernels','tools','models','docs']:
        source=ROOT/folder
        if source.exists():
            selected.update(f for f in source.rglob('*') if f.is_file() and 'backups' not in f.parts and '__pycache__' not in f.parts)
    for week in [5,6,7,8]:
        selected.update(f for f in latest(week).rglob('*') if f.is_file() and f.name!='delivery_status.json')
        selected.add(ROOT/'results'/f'week{week}_latest.txt')
    with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=5) as archive:
        for file in sorted(selected):archive.write(file,'full_project/'+file.relative_to(ROOT).as_posix())
        # The prior archive was independently verified and includes all four teaching weeks.
        prior=ROOT.parent/'循迹小车_复核后准确仿真工程.zip'
        assert prior.is_file(),'Prior reviewed four-week package is required.'
        with zipfile.ZipFile(prior) as old:
            assert old.testzip() is None
            previous_manifest=next(n for n in old.namelist() if n.endswith('/file_manifest.csv'))
            prefix=previous_manifest.rsplit('/',1)[0]+'/'
            previous_records=pd.read_csv(io.BytesIO(old.read(previous_manifest)))
            for _,row in previous_records.iterrows():
                raw=old.read(prefix+row.relative_path)
                assert hashlib.sha256(raw).hexdigest()==row.sha256
                assert len(raw)==row.bytes
            for item in old.infolist():
                if item.is_dir():continue
                name=item.filename
                if name.startswith('weeks1_4/'):
                    archive.writestr(name,old.read(item))
                else:
                    archive.writestr('weeks1_4/'+name,old.read(item))
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        assert 'full_project/START_PROJECT.m' in archive.namelist()
        assert 'full_project/models/LineFollowerTwin.slx' in archive.namelist()
        assert any(n.startswith('weeks1_4/') and n.endswith('.slx') for n in archive.namelist())
        entries=len(archive.namelist())
    delivery=dict(passed=True,archive=str(target),archive_bytes=target.stat().st_size,archive_sha256=digest(target),entries=entries,evidence_files=len(files),legacy_evidence_files=len(previous_records),all_evidence_hashes_verified=True,zip_crc_verified=True)
    (directory/'delivery_status.json').write_text(json.dumps(delivery,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'FULL_PROJECT_PACKAGE_PASSED entries={entries} bytes={target.stat().st_size} evidence_files={len(files)}',flush=True)

if __name__=='__main__':main()
