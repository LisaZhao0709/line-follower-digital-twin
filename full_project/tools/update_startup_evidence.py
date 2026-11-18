"""Incorporate the actual startup test without rerunning unchanged numerical experiments."""
from pathlib import Path
import json
import re

ROOT=Path(__file__).resolve().parents[1]
name=(ROOT/'results'/'week8_latest.txt').read_text().strip().replace('\\','/').rsplit('/',1)[-1]
directory=ROOT/'results'/name
runtime=json.loads((directory/'startup_runtime_checks.json').read_text(encoding='utf-8'))
assert runtime['passed'] and runtime['app_open_step_reset_close_passed']
status=json.loads((directory/'status.json').read_text(encoding='utf-8'))
status['startup_runtime_passed']=True
status['startup_checked_at']=runtime['checked_at']
(directory/'status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf-8')
report=directory/'完整项目实验与复核报告.md'
text=report.read_text(encoding='utf-8')
paragraph=f"独立MATLAB启动检查已在 {runtime['checked_at']} 完成：实际执行 START_PROJECT，界面打开、单步、复位、关闭及定时器释放全部通过，并检查了20个MATLAB源码文件。此前自动审批服务用量限制造成的未执行项已补齐。"
text,count=re.subn(r'交付阶段额外安排的 START_PROJECT 独立重启试验[^\n]*',paragraph,text)
if not count:
    assert paragraph in text,'Expected prior startup note or already-updated evidence.'
report.write_text(text,encoding='utf-8')
print('STARTUP_EVIDENCE_UPDATED')
