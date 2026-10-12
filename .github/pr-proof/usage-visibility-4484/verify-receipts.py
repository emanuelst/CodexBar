from pathlib import Path
import json
root=Path(__file__).resolve().parent
expected={
 '01-upgrade-preserved':(False,False,True,False),
 '02-reset-enabled':(False,True,True,False),
 '03-plan-hidden':(False,True,False,False),
 '04-global-on':(True,True,False,True),
 '05-extra-hidden-before-restart':(True,True,False,False),
 '06-after-restart':(True,True,False,False),
 '07-independent-after-restart':(False,True,True,False),
 '08-codex-plan-visible':(False,False,True,False),
 '09-codex-plan-hidden':(False,False,False,False),
 '10-reset-hidden':(False,False,True,False),
 '11-final':(False,True,True,False),
}
for step,values in expected.items():
    d=json.loads((root/('light-'+step+'.json')).read_text())
    assert (d['globalOptional'],d['menuResetsVisible'],d['menuPlanDateVisible'],d['menuExtraUsageVisible'])==values,step
    assert d['diskHiddenIDs']==d['hiddenIDs'],step
    assert d['menuMetrics']==d['previewMetrics'],step
    for name in ['Resets','PlanDate','ExtraUsage']:
        assert d['menu'+name+'Visible']==d['preview'+name+'Visible'],step
    if d['provider']=='claude': assert 'metric:secondary' in d['hiddenIDs'],step
before=json.loads((root/'light-05-extra-hidden-before-restart.json').read_text())
after=json.loads((root/'light-06-after-restart.json').read_text())
assert before['pid']!=after['pid']
assert {k:v for k,v in before.items() if k!='pid'}=={k:v for k,v in after.items() if k!='pid'}
print('PASS: 11 native app transition receipts, persisted old weekly choice, menu/preview parity, real restart with identical states and different PIDs.')
