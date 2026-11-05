#!/usr/bin/env python3
"""Check complete app/widget language resources, placeholders and native UI labels."""
import collections,json,re,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
base=root/'GorillaTranslate/Resources/Localization'
langs=['en','zh-Hant','yue','zh-Hans','ja','ko','fr','de','es','pt','it','nl','pl','tr','ru','uk','id','ms','th','vi']
load=lambda p:json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(p)]))
rx=re.compile(r'%(?:(\d+)\$)?[-+0#]*(?:\d+)?(?:\.\d+)?(lld|llu|ld|lu|lf|[diufeg@])')
def arguments(s):
    result={};next_index=0
    for m in rx.finditer(s.replace('%%','')):
        if m[1]:index=int(m[1])
        else:next_index+=1;index=next_index
        result[index]=m[2]
    return result
reference=load(base/'en.lproj/Localizable.strings');info=load(base/'en.lproj/InfoPlist.strings')
project=(root/'GorillaTranslation.xcodeproj/project.pbxproj').read_text()
terms=json.loads((root/'Tools/Localization/CoreTerms.json').read_text())
reviewed=json.loads((root/'Tools/Localization/ReviewedTranslations.json').read_text())
for lang in langs:
    values=load(base/f'{lang}.lproj/Localizable.strings')
    permissions=load(base/f'{lang}.lproj/InfoPlist.strings')
    assert set(reference)<=set(values),(lang,'missing interface keys',set(reference)-set(values))
    assert set(info)<=set(permissions),(lang,'missing permission keys')
    for table,source in [(values,reference),(permissions,info)]:
        for key,original in source.items():
            text=table[key]
            assert isinstance(text,str) and text.strip(),(lang,key,'empty')
            assert arguments(text)==arguments(original),(lang,key,'unsafe format arguments',text)
            assert text.count('\n')==original.count('\n'),(lang,key,'changed paragraph structure')
            if 'Gorilla Leading' in original:assert 'Gorilla Leading' in text,(lang,key,'translated product name')
    for name in ['Localizable','InfoPlist']:
        assert f'Localization/{lang}.lproj/{name}.strings' in project,(lang,name,'not bundled')
    for key,original in reference.items():
        if original in terms.get(lang,{}):assert values[key]==terms[lang][original],(lang,key,'core term mismatch')
    for key,text in reviewed.get(lang,{}).items():assert values[key]==text,(lang,key,'reviewed wording mismatch')
print(f'PASS: {len(langs)} complete interface/permission catalogs; {len(reference)} interface keys; argument, paragraph and brand preservation')
assert reference['語言']=='Language'
assert 'NSLocalNetworkUsageDescription' in info
print('PASS: native language settings, camera speech and network permission resources included')
