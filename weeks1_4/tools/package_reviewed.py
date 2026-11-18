"""Deliver the reviewed MATLAB project, frozen evidence and independent checker."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import csv
import hashlib

ROOT=Path(__file__).resolve().parents[1]
stored=Path((ROOT/'results'/'review_latest.txt').read_text(encoding='utf-8').strip())
review=ROOT/'results'/stored.name
assert (review/'independent_status.json').is_file()
# Verify all immutable review artefacts against the final recorded fingerprints.
with (review/'file_manifest.csv').open(encoding='utf-8',newline='') as source:
    for row in csv.DictReader(source):
        f=review/row['relative_path']
        assert hashlib.sha256(f.read_bytes()).hexdigest()==row['sha256'],str(f)

output=ROOT.parent/'循迹小车_复核后准确仿真工程.zip'
files=list(ROOT.glob('*.m'))+list(ROOT.glob('*.md'))
files+=list((ROOT/'kernels').glob('*.m'))
files+=[ROOT/'models'/f'{name}.slx' for name in ('LF_Week2_OpenLoop','LF_Week4_PD','LF_Week2_OpenLoop_Exact','LF_Week4_PD_Exact')]
files+=[ROOT/'data'/name for name in ('track_data.mat','track_source.png','track_mask.png','map_metadata.json')]
files+=list((ROOT/'results').glob('*.csv'))+list((ROOT/'results').glob('*.mat'))+list((ROOT/'results').glob('*.md'))
files+=list((ROOT/'results'/'figures').glob('*.png'))
files+=[ROOT/'results'/'review_latest.txt']
files+=list(f for f in review.rglob('*') if f.is_file())
files+=[ROOT/'tools'/'independent_review.py',ROOT/'tools'/'prepare_map.py',Path(__file__)]
files+=[ROOT/'review_delivery.log']
with ZipFile(output,'w',ZIP_DEFLATED) as z:
    for f in sorted(set(files)):
        assert f.is_file(),str(f)
        z.write(f,Path('weeks1_4')/f.relative_to(ROOT))
with ZipFile(output) as z:
    assert z.testzip() is None
    print('REVIEW_PACKAGE_OK entries=',len(z.namelist()),'bytes=',output.stat().st_size)
