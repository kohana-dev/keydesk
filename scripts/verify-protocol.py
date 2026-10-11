#!/usr/bin/env python3
import json, subprocess, pathlib
messages=['not-json',json.dumps({'foo':'invalid'}),json.dumps({'jsonrpc':'2.0','id':{},'method':'ping'}),json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/list'}),json.dumps({'jsonrpc':'2.0','id':2,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'keydesk-qa','version':'1'}}}),json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'}),json.dumps({'jsonrpc':'2.0','id':3,'method':'tools/list'}),json.dumps({'jsonrpc':'2.0','id':4,'method':'tools/call','params':{'name':'get_secret','arguments':{}}}),json.dumps({'jsonrpc':'2.0','id':5,'method':'ping'}),json.dumps({'jsonrpc':'2.0','id':6,'method':'initialize'}),json.dumps({'jsonrpc':'2.0','id':7,'method':'unknown-method'})]
p=subprocess.run(['dist/bin/keydesk','mcp','--project','00000000-0000-4000-8000-000000000001','--env','dev'],input='\n'.join(messages)+'\n',capture_output=True,text=True,timeout=10)
assert p.returncode==0 and not p.stderr
r=[json.loads(line) for line in p.stdout.splitlines()]
assert [item['error']['code'] for item in r[:4]]==[-32700,-32600,-32600,-32000]
assert r[4]['result']['protocolVersion']=='2025-11-25'
assert sorted(t['name'] for t in r[5]['result']['tools'])==['list_connections','request_access','revoke_access']
assert r[6]['error']['code']==-32602 and r[7]['result']=={}
assert r[8]['error']['code']==-32600 and r[9]['error']['code']==-32601
pathlib.Path('artifacts/protocol-verification.json').write_text(json.dumps({'passed':True,'stdout_only_json':True,'responses':r},indent=2,ensure_ascii=False))
print('JSON_RPC_LIFECYCLE_PARSE_ERRORS_NO_RAW_TOOLS_PASS')
