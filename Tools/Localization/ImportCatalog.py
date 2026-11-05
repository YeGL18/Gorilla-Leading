#!/usr/bin/env python3
"""Import on-device translations only after placeholder and coverage checks pass."""
import argparse, collections, json, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'GorillaTranslate/Resources/Localization'
LANGUAGES = ['en','zh-Hant','yue','zh-Hans','ja','ko','fr','de','es','pt','it','nl','pl','tr','ru','uk','id','ms','th','vi']
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+0#]*(?:\d+)?(?:\.\d+)?(lld|llu|ld|lu|lf|[diufeg@])', re.I)
def load(path):
    return json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(path)])) if path.exists() else {}
def format_tokens(s):
    result={};next_index=0
    for m in FORMAT.finditer(s.replace('%%','')):
        if m[1]: index=int(m[1])
        else: next_index+=1;index=next_index
        result[index]=m[2].lower()
    return result
def repair(original, value):
    expected = {m[0].lower():m[0] for m in FORMAT.finditer(original.replace('%%',''))}
    value = FORMAT.sub(lambda m: expected.get(m[0].lower(),m[0]),value)
    if value.count('\n') > original.count('\n'):
        value = re.sub(r'\n+', '\n', value)
    # Retain spacing used by concatenated labels, e.g. "You: " and status suffixes.
    value = value.strip()
    if original.startswith(' '): value = ' ' + value
    if original.endswith(' '): value += ' '
    return value

def main():
    parser=argparse.ArgumentParser();parser.add_argument('cache',type=Path);parser.add_argument('--write',action='store_true');args=parser.parse_args()
    source=load(BASE/'en.lproj/Localizable.strings'); info=load(BASE/'en.lproj/InfoPlist.strings')
    terms=json.loads((ROOT/'Tools/Localization/CoreTerms.json').read_text())
    manual_path=ROOT/'Tools/Localization/ReviewedTranslations.json'
    manual=json.loads(manual_path.read_text()) if manual_path.exists() else {}
    staged={};issues={}
    for lang in LANGUAGES:
        if lang=='en':continue
        existing=load(BASE/f'{lang}.lproj/Localizable.strings') | load(BASE/f'{lang}.lproj/InfoPlist.strings')
        file=args.cache/f'{lang}.json'
        data=json.loads(file.read_text()) if file.exists() else {}
        review=args.cache/f'{lang}.review.json'
        if review.exists(): data={**json.loads(review.read_text()),**data}
        if lang=='yue': data=dict(staged.get('zh-Hant',{}))
        data.update(existing)
        out={}
        for key,original in {**source,**info}.items():
            value=manual.get(lang,{}).get(key,data.get(key))
            if original in terms.get(lang,{}): value=terms[lang][original]
            if value is None:
                issues.setdefault(lang,[]).append({'key':key,'reason':'missing'});continue
            value=repair(original,value)
            if format_tokens(value)!=format_tokens(original):
                issues.setdefault(lang,[]).append({'key':key,'reason':'format','value':value});continue
            if 'Gorilla Leading' in original and 'Gorilla Leading' not in value:
                issues.setdefault(lang,[]).append({'key':key,'reason':'brand','value':value});continue
            if value.count('\n')!=original.count('\n'):
                issues.setdefault(lang,[]).append({'key':key,'reason':'newlines','value':value});continue
            out[key]=value
        staged[lang]=out
    report=ROOT/'outputs/localization/review.json';report.parent.mkdir(parents=True,exist_ok=True);report.write_text(json.dumps(issues,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({lang:len(rows) for lang,rows in issues.items()},ensure_ascii=False))
    if issues: raise SystemExit('Translation coverage/format review remains; resources were not written.')
    if args.write:
        for lang,values in staged.items():
            directory=BASE/f'{lang}.lproj';directory.mkdir(exist_ok=True)
            for name,table in [('Localizable',source),('InfoPlist',info)]:
                path=directory/f'{name}.strings';old=load(path)
                additions={k:values[k] for k in table if k not in old}
                if path.exists():
                    content=path.read_text()
                    overrides={k:values[k] for k in table if k in old and old[k]!=values[k]
                               and (table[k] in terms.get(lang,{}) or k in manual.get(lang,{}))}
                    for k,v in overrides.items():
                        quoted=json.dumps(k,ensure_ascii=False)
                        pattern=re.compile(r'^'+re.escape(quoted)+r'\s*=.*?;[ \t]*$',re.M)
                        assert pattern.search(content),(lang,k,'override key not found')
                        line=quoted+' = '+json.dumps(v,ensure_ascii=False)+';'
                        content=pattern.sub(lambda m:line,content)
                    if additions:
                        content+='\n/* Additional interface translations, generated and checked locally. */\n'
                        content+=''.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';\n' for k,v in additions.items())
                    if overrides or additions:path.write_text(content)
                else:
                    path.write_text('/* Gorilla Leading localization, generated and checked locally. */\n'+''.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(values[k],ensure_ascii=False)+';\n' for k in table))
        print('Imported complete catalogs for all 20 languages.')
if __name__=='__main__': main()
