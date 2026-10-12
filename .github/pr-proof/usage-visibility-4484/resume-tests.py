from pathlib import Path
from dataclasses import asdict
import json, re, sys, tempfile
sys.path.insert(0,str(Path.cwd()/'Scripts'))
import ci_swift_test_by_suite as runner
import direct_swift_test_groups as direct
log=Path('/private/tmp/codexbar-4484-review-full.log').read_text()
logged={int(n):json.loads(names) for n,names in re.findall(r'^Selected group (\d+): (\[.*\])$',log,re.M)}
started=set(map(int,re.findall(r'::group::Direct Swift test group (\d+)/150',log)))
inventory=[]
selections=runner.prioritized_suites(runner.swift_test_list(['swift'],inventory))
groups=list(runner.test_groups(selections,12))
assert len(groups)==len(logged)==150
for i,g in enumerate(groups,1):
    assert [s.name for s in g]==logged[i],i
missing=sorted(set(logged)-started)
print('Byte-identical group selections verified; resuming original groups:',missing,flush=True)
root=Path(tempfile.mkdtemp(prefix='codexbar-4484-resumed-'))
selected=[[asdict(s) for s in groups[i-1]] for i in missing]
runtime=direct.prepare_runtime(['swift'],selected,inventory,root)
manifest=root/'manifest.json'
manifest.write_text(json.dumps({'runtime':runtime,'groups':selected,'timeout':180,'workers':4,'retry_non_timeout_failures':True}))
result=runner.run_command([sys.executable,str(Path.cwd()/'Scripts/direct_swift_test_groups.py'),str(manifest)],timeout=direct.pool_timeout(selected,180,True,len(runtime['products'])))
records=json.loads((root/'results.json').read_text())
print('Resume result:',{'selected':len(selected),'passed':sum(r['code']==0 for r in records),'timedOut':sum(r['timed_out'] for r in records)},flush=True)
sys.exit(result)
