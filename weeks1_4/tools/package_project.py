"""Package deliverables only, excluding failed-attempt logs and build caches."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parent / '循迹小车_前四周_MATLAB工程.zip'
files = list(ROOT.glob('*.m')) + list(ROOT.glob('*.md'))
files += list((ROOT/'kernels').glob('*.m'))
files += [(ROOT/'models'/n) for n in ('LF_Week2_OpenLoop.slx', 'LF_Week4_PD.slx')]
files += [(ROOT/'data'/n) for n in ('track_source.png','track_mask.png','track_data.mat','map_metadata.json')]
files += list((ROOT/'results').glob('*.csv')) + list((ROOT/'results').glob('*.mat')) + list((ROOT/'results').glob('*.md'))
files += list((ROOT/'results'/'figures').glob('*.png'))
files += [ROOT/'validation.log',ROOT/'delivery.log']
with ZipFile(OUTPUT, 'w', ZIP_DEFLATED) as archive:
    for f in sorted(set(files)):
        assert f.is_file(), str(f)
        archive.write(f, Path('weeks1_4') / f.relative_to(ROOT))
with ZipFile(OUTPUT) as archive:
    assert archive.testzip() is None
    print('entries',len(archive.namelist()),'bytes',OUTPUT.stat().st_size,'output',OUTPUT)
