#!/usr/bin/env python3
"""Real client smoke test against an explicitly isolated demo socket, no provider keys."""
import argparse, json, os, pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser();parser.add_argument('client',choices=['codex','claude']);args=parser.parse_args()
config=json.loads(pathlib.Path(os.environ.get('KEYDESK_MCP_QA_CONFIG',str(root/'artifacts/mcp-demo-v0.4.0.json'))).read_text())
server=config['mcpServers']['keydesk'];server['env']={'KEYDESK_SOCKET_PATH':'/tmp/keydesk-v021-qa/cli.sock'}
prompt='''This is a disposable Keydesk MCP integration test with fake data and no external provider calls. Use only Keydesk MCP tools. Do not use shell, file, web, other MCP tools, or inspect credentials. First call list_connections without a grant and confirm denial. Then request_access with operation metadata, duration 120, maximumCalls 2. The tester will approve in the local demo app. Call list_connections, then revoke_access with the returned grantId. Call list_connections once more to confirm denial. Report the observed steps and never request or reveal a key value. Do not call provider operations.'''
with tempfile.TemporaryDirectory(prefix='keydesk-ai-fixture-') as directory:
    if args.client=='codex':
        settings=['mcp_servers.keydesk.command='+json.dumps(server['command'],ensure_ascii=False),'mcp_servers.keydesk.args='+json.dumps(server['args']),'mcp_servers.keydesk.env='+ '{ KEYDESK_SOCKET_PATH = "/tmp/keydesk-v021-qa/cli.sock" }']
        command=['codex','exec','--ignore-user-config','--ignore-rules','--ephemeral','--skip-git-repo-check','--sandbox','read-only','--json','--cd',directory]
        for setting in settings:command+=['-c',setting]
        command+=['-c','mcp_servers.keydesk.enabled_tools=[\"list_connections\",\"request_access\",\"revoke_access\"]']
        for tool in ['list_connections','request_access','revoke_access']:command+=['-c',f'mcp_servers.keydesk.tools.{tool}.approval_mode=\"approve\"']
        command+=[prompt]
    else:
        command=['claude','--restricted','--strict-mcp-config','--mcp-config',json.dumps(config,ensure_ascii=False),'--tools','','--allowedTools','mcp__keydesk__list_connections,mcp__keydesk__request_access,mcp__keydesk__revoke_access','--permission-prompts','none','--no-session-persistence','--output-format','stream-json','--verbose','--print',prompt]
    output=root/'artifacts'/f'{args.client}-real-client-v0.4.0.jsonl'
    error=root/'artifacts'/f'{args.client}-real-client-v0.4.0.stderr.txt'
    with output.open('w') as stdout,error.open('w') as stderr:
        process=subprocess.Popen(command,cwd=directory,stdout=stdout,stderr=stderr,env=os.environ)
        print(f'{args.client.upper()}_REAL_CLIENT_STARTED_PID={process.pid}',flush=True)
        try:code=process.wait(timeout=180)
        except subprocess.TimeoutExpired:process.terminate();process.wait(timeout=10);code=124
    (root/'artifacts'/f'{args.client}-real-client-exit.json').write_text(json.dumps({'exit_code':code,'mode':'isolated demo metadata only','provider_network_calls':False},indent=2)+'\n')
    print(f'{args.client.upper()}_REAL_CLIENT_EXIT={code}',flush=True)
