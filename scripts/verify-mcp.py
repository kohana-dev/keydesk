#!/usr/bin/env python3
import json, os, pathlib, subprocess, select, time
config=json.loads(pathlib.Path(os.environ.get('KEYDESK_MCP_QA_CONFIG','artifacts/mcp-demo-config.json')).read_text())['mcpServers']['keydesk']
p=subprocess.Popen([config['command']]+config['args'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={**os.environ,'KEYDESK_SOCKET_PATH':'/tmp/keydesk-v021-qa/cli.sock'},text=True,bufsize=1)
log=[]
def send(id,method,params=None):
    value={'jsonrpc':'2.0','method':method}
    if id is not None:value['id']=id
    if params is not None:value['params']=params
    p.stdin.write(json.dumps(value)+'\n');p.stdin.flush()
def receive(id,timeout=80):
    assert select.select([p.stdout],[],[],timeout)[0], 'MCP response timeout'
    result=json.loads(p.stdout.readline());assert result.get('id')==id
    log.append(result);return result
def call(id,name,arguments):send(id,'tools/call',{'name':name,'arguments':arguments});return receive(id)
send(1,'initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'keydesk-qa','version':'1'}})
assert receive(1)['result']['protocolVersion']=='2025-11-25'
send(None,'notifications/initialized')
send(2,'tools/list');tools=receive(2)['result']['tools'];assert sorted(t['name'] for t in tools)==['list_connections','request_access','revoke_access']
assert not any(t['name'] in ['get_secret','copy_secret','exec'] for t in tools)
assert call(3,'list_connections',{})['result']['isError']
send(4,'tools/call',{'name':'request_access','arguments':{'operation':'metadata','duration':120,'maximumCalls':3}})
print('WAITING_FOR_DEMO_METADATA_APPROVAL',flush=True)
grant=receive(4)['result']['structuredContent']['grantId']
listed=call(5,'list_connections',{})['result']['structuredContent'];variables=listed['variables']
assert len(variables)==4 and all(set(v)=={'variable','provider'} for v in variables) and 'keydesk run' in listed['usage']
assert call(6,'revoke_access',{'grantId':grant})['result']['structuredContent']['revoked']
assert call(7,'list_connections',{})['result']['isError']
send(8,'tools/call',{'name':'perform_operation','arguments':{}});assert receive(8)['error']['code']==-32602
send(12,'tools/call',{'name':'get_secret','arguments':{}});assert receive(12)['error']['code']==-32602
send(13,'ping');assert receive(13)['result']=={}
assert 'DEMO_ONLY_' not in json.dumps(log)
p.stdin.close();p.wait(timeout=5);assert p.returncode==0
pathlib.Path('artifacts/mcp-verification-v0.4.0.json').write_text(json.dumps({'passed':True,'network':'none','tools':'metadata only','responses':log},indent=2,ensure_ascii=False))
print('MCP_METADATA_ONLY_APPROVAL_QUOTA_REVOCATION_PASS',flush=True)
