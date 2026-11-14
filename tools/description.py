"""The user-approved package description; applies to both package layouts."""
import copy,json
DESCRIPTION='把iOS18控制中心完整移植到iOS16/17:添加页面、自定义每个按钮、直接在控制中心里移动或移除它们。'
DEPICTION='Library/PreferenceBundles/ControlCenter18Prefs.bundle/Depiction/depiction.json'
def put(entries,name,data):
    info=copy.copy(entries[name][0]);info.size=len(data);entries[name]=(info,data)
def apply_description(control,data):
    lines=[];skip=False;found=False
    for line in control['control'][1].decode('utf-8').splitlines():
        if line.startswith((' ','\t')):
            if not skip:lines.append(line)
            continue
        skip=line.startswith('Description:')
        if skip:lines.append('Description: '+DESCRIPTION);found=True
        else:lines.append(line)
    assert found
    put(control,'control',('\n'.join(lines).rstrip()+'\n').encode())
    obj=json.loads(data[DEPICTION][1]);obj['tabs']=[{'tabname':'详情','class':'DepictionStackView','views':[{'class':'DepictionMarkdownView','markdown':DESCRIPTION}]}]
    put(data,DEPICTION,(json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode())
def verify_description(control,data):
    from integrity import fields
    assert fields(control['control'][1])['Description']==DESCRIPTION
    obj=json.loads(data[DEPICTION][1]);assert obj['tabs']==[{'tabname':'详情','class':'DepictionStackView','views':[{'class':'DepictionMarkdownView','markdown':DESCRIPTION}]}]
